# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::ValidateIncomingWebhookService do
  subject(:result) { described_class.call(payload:, signature:, payment_provider:) }

  let(:payment_provider) { build(:authorize_net_provider, signature_key: "56E529FB8ABC") }
  let(:payload) { File.read(Rails.root.join("spec/fixtures/authorize_net/webhook_fraud_approved.json")) }
  let(:signature) { "sha512=#{OpenSSL::HMAC.hexdigest("SHA512", "56E529FB8ABC", payload).upcase}" }

  it "accepts a body signed with the signature key" do
    expect(result).to be_success
  end

  context "when the body was changed" do
    let(:signature) { "sha512=#{OpenSSL::HMAC.hexdigest("SHA512", "56E529FB8ABC", "#{payload} ").upcase}" }

    it "rejects it" do
      expect(result).to be_failure
      expect(result.error.code).to eq("webhook_error")
    end
  end

  context "when the signature header is missing" do
    let(:signature) { nil }

    it "rejects it" do
      expect(result).to be_failure
      expect(result.error.code).to eq("webhook_error")
    end
  end

  context "when the provider has no signature key" do
    let(:payment_provider) { build(:authorize_net_provider, signature_key: nil) }

    it "rejects it" do
      expect(result).to be_failure
      expect(result.error.code).to eq("webhook_error")
    end
  end
end
