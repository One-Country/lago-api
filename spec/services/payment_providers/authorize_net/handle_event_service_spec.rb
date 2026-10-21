# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::HandleEventService do
  subject(:result) { described_class.call(payment_provider: authorize_net_provider, event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "authorize_net") }

  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }
  let(:authorize_net_customer) do
    create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: "519123456")
  end
  let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 2500, currency: "USD", payment_status: :pending) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider: authorize_net_provider,
      payment_provider_customer: authorize_net_customer,
      provider_payment_id: "80042512347",
      amount_cents: 2500,
      amount_currency: "USD",
      status: "held_for_review",
      payable_payment_status: "processing"
    )
  end

  def fixture(name)
    JSON.parse(File.read(Rails.root.join("spec/fixtures/authorize_net", name)))
  end

  context "when a held charge is approved" do
    let(:event) { fixture("webhook_fraud_approved.json") }

    before { payment }

    it "marks the payment and the invoice succeeded" do
      expect(result).to be_success
      expect(payment.reload).to have_attributes(status: "approved", payable_payment_status: "succeeded")
      expect(invoice.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 2500)
      expect(SendWebhookJob).to have_been_enqueued.with("payment.succeeded", payment)
    end
  end

  context "when a held charge is declined" do
    let(:event) { fixture("webhook_fraud_approved.json").merge("eventType" => "net.authorize.payment.fraud.declined") }

    before { payment }

    it "marks the payment and the invoice failed" do
      expect(result).to be_success
      expect(payment.reload).to have_attributes(status: "declined", payable_payment_status: "failed")
      expect(invoice.reload).to have_attributes(payment_status: "failed", ready_for_payment_processing: true)
    end
  end

  context "when the transaction is not a Lago payment" do
    let(:event) { fixture("webhook_fraud_approved.json").deep_merge("payload" => {"id" => "999"}) }

    it "ignores it" do
      expect(result).to be_success
      expect(result.payment).to be_nil
    end
  end

  context "when a payment profile is added to a linked customer profile" do
    let(:event) { fixture("webhook_payment_profile_created.json") }

    before { authorize_net_customer }

    it "syncs the customer's payment methods" do
      expect(result).to be_success
      expect(PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsJob).to have_been_enqueued.with(authorize_net_customer)
    end
  end

  context "when the customer profile is not linked to a Lago customer" do
    let(:event) { fixture("webhook_payment_profile_created.json").deep_merge("payload" => {"customerProfileId" => 1}) }

    it "ignores it" do
      expect(result).to be_success
      expect(PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsJob).not_to have_been_enqueued
    end
  end

  context "with an event the provider does not handle" do
    let(:event) { fixture("webhook_fraud_approved.json").merge("eventType" => "net.authorize.payment.authcapture.created") }

    before { payment }

    it "ignores it" do
      expect(result).to be_success
      expect(payment.reload.status).to eq("held_for_review")
    end
  end
end
