# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::AuthorizeNetService do
  let(:organization) { create(:organization) }

  let(:customer) { create(:customer, organization:, external_id: "cus_1234567890_abcdefghij", email: "member@example.com", name: "Pat Member") }
  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }
  let(:authorize_net_customer) do
    create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: nil)
  end
  let(:api_url) { "https://apitest.authorize.net/xml/v1/request.api" }

  describe ".call(:create)" do
    subject(:result) { described_class.call(:create, authorize_net_customer) }

    let(:fixture) { "create_customer_profile.json" }

    before do
      stub_request(:post, api_url)
        .with(body: hash_including("createCustomerProfileRequest"))
        .to_return(status: 200, body: File.read(Rails.root.join("spec/fixtures/authorize_net", fixture)))
    end

    it "creates the customer profile and saves its ID" do
      expect(result).to be_success
      expect(authorize_net_customer.reload.provider_customer_id).to eq("519123456")
      expect(SendWebhookJob).to have_been_enqueued.with("customer.payment_provider_created", customer)
      expect(WebMock).to(have_requested(:post, api_url).with do |request|
        expect(JSON.parse(request.body).dig("createCustomerProfileRequest", "profile")).to eq(
          "merchantCustomerId" => "cus_1234567890_abcde",
          "description" => "Pat Member",
          "email" => "member@example.com"
        )
      end)
    end

    context "when a profile already exists for the customer" do
      let(:fixture) { "create_customer_profile_duplicate.json" }

      it "links the existing profile" do
        expect(result).to be_success
        expect(authorize_net_customer.reload.provider_customer_id).to eq("519999999")
      end
    end

    context "when Authorize.net rejects the request" do
      before do
        stub_request(:post, api_url).to_return(
          status: 200,
          body: {messages: {resultCode: "Error", message: [{code: "E00007", text: "User authentication failed due to invalid authentication values."}]}}.to_json
        )
      end

      it "sends an error webhook and returns a failure" do
        expect(result).to be_failure
        expect(authorize_net_customer.reload.provider_customer_id).to be_nil
        expect(SendWebhookJob).to have_been_enqueued.with(
          "customer.payment_provider_error",
          customer,
          provider_error: {message: "User authentication failed due to invalid authentication values.", error_code: "E00007"}
        )
      end
    end

    context "when the customer is already linked" do
      let(:authorize_net_customer) do
        create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: "519000000")
      end

      it "does nothing" do
        expect(result).to be_success
        expect(WebMock).not_to have_requested(:post, api_url)
      end
    end
  end

  describe ".call(:generate_checkout_url)" do
    subject(:result) { described_class.call(:generate_checkout_url, authorize_net_customer) }

    it "is not supported" do
      expect(result).to be_failure
      expect(result.error.messages[:base]).to eq(["checkout_url_not_supported"])
    end
  end
end
