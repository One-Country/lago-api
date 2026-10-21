# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::HandleIncomingWebhookService do
  subject(:result) { described_class.call(inbound_webhook:) }

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:authorize_net_provider, organization:, code: "authorize_net_1") }
  let(:payload) { File.read(Rails.root.join("spec/fixtures/authorize_net/webhook_fraud_approved.json")) }
  let(:inbound_webhook) do
    create(:inbound_webhook, organization:, source: "authorize_net", code: payment_provider.code, payload:, event_type: "net.authorize.payment.fraud.approved")
  end

  before do
    allow(PaymentProviders::AuthorizeNet::HandleEventService).to receive(:call!).and_call_original
  end

  it "handles the event with the provider it was sent to" do
    expect(result).to be_success
    expect(result.event["eventType"]).to eq("net.authorize.payment.fraud.approved")
    expect(PaymentProviders::AuthorizeNet::HandleEventService).to have_received(:call!)
      .with(payment_provider:, event: JSON.parse(payload))
  end

  context "when the payload is not JSON" do
    let(:payload) { "not json" }

    it "returns a webhook error" do
      expect(result).to be_failure
      expect(result.error.code).to eq("webhook_error")
    end
  end

  context "when the provider no longer exists" do
    let(:inbound_webhook) do
      create(:inbound_webhook, organization:, source: "authorize_net", code: "gone", payload:, event_type: "net.authorize.payment.fraud.approved")
    end

    it "returns a webhook error" do
      expect(result).to be_failure
      expect(result.error.code).to eq("webhook_error")
    end
  end
end
