# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::Payments::ReconcileService do
  subject(:result) { described_class.call(payment:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, payment_provider: "authorize_net") }

  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }
  let(:authorize_net_customer) { create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider) }
  let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 2500, currency: "USD", payment_status: :pending) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider: authorize_net_provider,
      payment_provider_customer: authorize_net_customer,
      provider_payment_id: nil,
      amount_cents: 2500,
      amount_currency: "USD",
      status: "held_for_review",
      payable_payment_status: "processing",
      error_code: "11"
    )
  end
  let(:listed) { JSON.parse(File.read(Rails.root.join("spec/fixtures/authorize_net/unsettled_transaction_list.json"))) }
  let(:api_url) { "https://apitest.authorize.net/xml/v1/request.api" }

  before do
    stub_request(:post, api_url).to_return { {status: 200, body: listed.to_json} }
  end

  context "when the earlier transaction is now listed" do
    before { listed["transactions"][0]["invoiceNumber"] = PaymentProviders::AuthorizeNet::Payments::CreateService.invoice_number(payment) }

    it "settles the payment with that transaction" do
      expect(result).to be_success
      expect(payment.reload).to have_attributes(provider_payment_id: "80042512399", status: "approved", payable_payment_status: "succeeded")
      expect(invoice.reload.payment_status).to eq("succeeded")
    end
  end

  context "when it is still not listed" do
    it "leaves the payment processing" do
      expect(result).to be_success
      expect(payment.reload).to have_attributes(provider_payment_id: nil, payable_payment_status: "processing")
    end
  end

  context "when the payment was already settled" do
    before { payment.update!(provider_payment_id: "80042512399", status: "approved", payable_payment_status: "succeeded") }

    it "does nothing" do
      expect(result).to be_success
      expect(WebMock).not_to have_requested(:post, api_url)
    end
  end
end
