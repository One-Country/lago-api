# frozen_string_literal: true

require "rails_helper"

# This file does not run on CI because it's suffixed `_integration_spec.rb`
#
# It sends real requests to the Authorize.net sandbox: it creates a customer
# profile and a payment profile, syncs it as a payment method, charges an
# invoice, then replays a charge to check that a duplicate is reconciled with
# the earlier transaction instead of charging twice. The customer profile is
# deleted at the end.
#
#   AUTHORIZE_NET_API_LOGIN_ID=... AUTHORIZE_NET_TRANSACTION_KEY=... \
#     bundle exec rspec spec/integration/authorize_net/payment_integration_spec.rb

describe "Authorize.net Payment Integration Test", type: :request do
  let(:organization) { create(:organization, name: "Authorize.net IRL") }
  let(:customer) { create(:customer, organization:, external_id: "lago-#{SecureRandom.hex(6)}", currency: "USD", payment_provider: "authorize_net") }
  let(:provider) do
    PaymentProviders::AuthorizeNetService.new.create_or_update(
      organization:,
      code: "authorize_net_spec",
      name: "Authorize.net Spec",
      api_login_id: ENV["AUTHORIZE_NET_API_LOGIN_ID"],
      transaction_key: ENV["AUTHORIZE_NET_TRANSACTION_KEY"],
      environment: "sandbox"
    ).authorize_net_provider
  end
  let(:client) { PaymentProviders::AuthorizeNet::Client.new(provider) }
  let(:provider_customer) { customer.reload.authorize_net_customer }

  before do
    raise "You need to set AUTHORIZE_NET_API_LOGIN_ID and AUTHORIZE_NET_TRANSACTION_KEY" unless ENV["AUTHORIZE_NET_API_LOGIN_ID"]

    WebMock.disable_net_connect!(allow: "apitest.authorize.net")
  end

  after do
    if provider_customer&.provider_customer_id
      client.call("deleteCustomerProfileRequest", {customerProfileId: provider_customer.provider_customer_id})
    end
  end

  def invoice_for(amount_cents)
    create(:invoice, organization:, customer:, invoice_type: :one_off, currency: "USD", total_amount_cents: amount_cents, payment_status: :pending)
  end

  it "charges a stored payment profile and reconciles a replayed charge" do
    # A customer profile created on Authorize.net
    PaymentProviders::CreateCustomerFactory.new_instance(
      provider: "authorize_net",
      customer:,
      payment_provider_id: provider.id,
      params: {sync_with_provider: true},
      async: false
    ).call.raise_if_error!
    expect(provider_customer.provider_customer_id).to be_present

    # A card stored by the merchant's own checkout, then synced into Lago
    stored = client.call(
      "createCustomerPaymentProfileRequest",
      {
        customerProfileId: provider_customer.provider_customer_id,
        paymentProfile: {
          customerType: "individual",
          payment: {creditCard: {cardNumber: "4111111111111111", expirationDate: "2035-12"}}
        },
        validationMode: "none"
      }
    )
    expect(stored).to be_ok

    PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsService.call!(provider_customer:)
    payment_method = customer.reload.default_payment_method
    expect(payment_method).to have_attributes(provider_method_id: stored["customerPaymentProfileId"])
    expect(payment_method.details).to include("last4" => "1111", "brand" => "visa", "expiration_year" => 2035)

    # Lago charges an invoice through the provider
    invoice = invoice_for(rand(1_000..9_999))
    Invoices::Payments::CreateService.call!(invoice:, payment_provider: :authorize_net)

    payment = invoice.reload.payments.sole
    expect(invoice.payment_status).to eq("succeeded")
    expect(payment).to have_attributes(status: "approved", payable_payment_status: "succeeded", payment_method_id: payment_method.id)
    expect(payment.provider_payment_id).to match(/\A\d+\z/)

    # A retried job after a lost response: the same payment is charged again
    replay = invoice_for(rand(1_000..9_999))
    Invoices::Payments::CreateService.call!(invoice: replay, payment_provider: :authorize_net)
    first = replay.reload.payments.sole
    first_transaction_id = first.provider_payment_id
    first.update!(status: "pending", payable_payment_status: "pending", provider_payment_id: nil)
    replay.update!(payment_status: :pending)

    PaymentProviders::AuthorizeNet::Payments::CreateService.call!(payment: first.reload, reference: "replay", metadata: {})

    expect(first.reload).to have_attributes(
      status: "approved",
      payable_payment_status: "succeeded",
      provider_payment_id: first_transaction_id
    )
  end
end
