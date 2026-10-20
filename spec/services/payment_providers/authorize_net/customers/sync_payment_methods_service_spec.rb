# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsService do
  subject(:result) { described_class.call(provider_customer: authorize_net_customer) }

  let_it_be(:organization) { create(:organization) }

  let(:customer) { create(:customer, organization:, payment_provider: "authorize_net") }
  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }
  let(:authorize_net_customer) do
    create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: "519123456")
  end
  let(:api_url) { "https://apitest.authorize.net/xml/v1/request.api" }
  let(:profile) { JSON.parse(File.read(Rails.root.join("spec/fixtures/authorize_net/get_customer_profile.json"))) }

  before do
    stub_request(:post, api_url)
      .with(body: hash_including("getCustomerProfileRequest"))
      .to_return { {status: 200, body: profile.to_json} }
  end

  it "creates a payment method per payment profile, with its card details" do
    expect(result).to be_success
    expect(customer.payment_methods.order(:provider_method_id).map { |pm| [pm.provider_method_id, pm.details] }).to eq(
      [
        ["527000001", {"type" => "card", "last4" => "1111", "brand" => "visa", "expiration_month" => 12, "expiration_year" => 2035}],
        ["527000002", {"type" => "card", "last4" => "0002", "brand" => "mastercard", "expiration_month" => 4, "expiration_year" => 2031}]
      ]
    )
  end

  it "makes Authorize.net's default profile the default when the customer has none" do
    result

    expect(customer.default_payment_method.provider_method_id).to eq("527000002")
  end

  it "asks for unmasked expiration dates" do
    result

    expect(WebMock).to(have_requested(:post, api_url).with do |request|
      expect(JSON.parse(request.body)["getCustomerProfileRequest"].except("merchantAuthentication")).to eq(
        "customerProfileId" => "519123456",
        "unmaskExpirationDate" => true
      )
    end)
  end

  context "when every payment profile is already a payment method" do
    before do
      create(:payment_method, customer:, payment_provider_customer: authorize_net_customer, provider_method_id: "527000001", is_default: true)
      create(:payment_method, customer:, payment_provider_customer: authorize_net_customer, provider_method_id: "527000002", is_default: false)
    end

    it "keeps Lago's default" do
      result

      expect(customer.default_payment_method.provider_method_id).to eq("527000001")
    end
  end

  context "when a new payment profile was added at Authorize.net" do
    before do
      profile["profile"]["paymentProfiles"][1].delete("defaultPaymentProfile")
      create(:payment_method, customer:, payment_provider_customer: authorize_net_customer, provider_method_id: "527000001", is_default: true)
    end

    it "makes the new payment method the default" do
      result

      expect(customer.default_payment_method.provider_method_id).to eq("527000002")
    end
  end

  context "when a payment profile was removed at Authorize.net" do
    let!(:removed) do
      create(:payment_method, customer:, payment_provider_customer: authorize_net_customer, provider_method_id: "527000009", is_default: true)
    end

    it "removes its payment method and picks a new default" do
      result

      expect(removed.reload).to be_discarded
      expect(customer.payment_methods.pluck(:provider_method_id)).to match_array(%w[527000001 527000002])
      expect(customer.default_payment_method.provider_method_id).to eq("527000002")
    end
  end

  context "when the customer profile does not exist" do
    let(:profile) { {"messages" => {"resultCode" => "Error", "message" => [{"code" => "E00040", "text" => "The record cannot be found."}]}} }

    it "returns a failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("E00040")
    end
  end

  context "when the provider customer has no profile ID" do
    let(:authorize_net_customer) do
      create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: nil)
    end

    it "does nothing" do
      expect(result).to be_success
      expect(WebMock).not_to have_requested(:post, api_url)
    end
  end
end
