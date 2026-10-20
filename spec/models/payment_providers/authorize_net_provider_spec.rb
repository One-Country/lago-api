# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNetProvider do
  subject(:authorize_net_provider) { build(:authorize_net_provider) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:api_login_id) }
    it { is_expected.to validate_presence_of(:transaction_key) }
    it { is_expected.to validate_inclusion_of(:environment).in_array(%w[sandbox production]) }

    it "validates uniqueness of the code" do
      expect(authorize_net_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "#api_url" do
    it "returns the sandbox endpoint for the sandbox environment" do
      expect(authorize_net_provider.api_url).to eq("https://apitest.authorize.net/xml/v1/request.api")
    end

    context "with the production environment" do
      subject(:authorize_net_provider) { build(:authorize_net_provider, environment: "production") }

      it "returns the production endpoint" do
        expect(authorize_net_provider.api_url).to eq("https://api.authorize.net/xml/v1/request.api")
      end
    end
  end

  describe "#determine_payment_status" do
    it "maps the transaction statuses to payment statuses" do
      expect(authorize_net_provider.determine_payment_status("approved")).to eq(:succeeded)
      expect(authorize_net_provider.determine_payment_status("held_for_review")).to eq(:processing)
      expect(authorize_net_provider.determine_payment_status("declined")).to eq(:failed)
      expect(authorize_net_provider.determine_payment_status("error")).to eq(:failed)
    end
  end

  describe "#webhook_end_point" do
    subject(:authorize_net_provider) { create(:authorize_net_provider, code: "authorize net") }

    it "returns the provider's webhook URL" do
      expect(authorize_net_provider.webhook_end_point.to_s).to eq(
        "#{ENV["LAGO_API_URL"]}/webhooks/authorize_net/#{authorize_net_provider.organization_id}?code=authorize+net"
      )
    end
  end

  describe "#payment_type" do
    it "returns authorize_net" do
      expect(authorize_net_provider.payment_type).to eq("authorize_net")
    end
  end
end
