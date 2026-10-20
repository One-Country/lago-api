# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNetService do
  subject(:authorize_net_service) { described_class.new }

  include_context "with mocked security logger"

  let_it_be(:organization) { create(:organization) }

  describe "#create_or_update" do
    let(:args) do
      {
        organization:,
        code: "authorize_net_1",
        name: "Authorize.net",
        api_login_id: "5KP3u95bQpv",
        transaction_key: "346HZ32z3fP4hTG2",
        signature_key: "56E529FB8ABC",
        environment: "sandbox"
      }
    end

    context "when creating a new provider" do
      it "creates an Authorize.net provider" do
        result = authorize_net_service.create_or_update(**args)

        expect(result).to be_success
        expect(result.authorize_net_provider).to have_attributes(
          organization_id: organization.id,
          code: "authorize_net_1",
          name: "Authorize.net",
          api_login_id: "5KP3u95bQpv",
          transaction_key: "346HZ32z3fP4hTG2",
          signature_key: "56E529FB8ABC",
          environment: "sandbox"
        )
      end

      it_behaves_like "produces a security log", "integration.created" do
        before { authorize_net_service.create_or_update(**args) }
      end
    end

    context "when the environment is invalid" do
      it "returns a validation failure" do
        result = authorize_net_service.create_or_update(**args, environment: "live")

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:environment]).to eq(["value_is_invalid"])
      end
    end

    context "when updating an existing provider" do
      let!(:existing_provider) do
        create(:authorize_net_provider, organization:, code: "authorize_net_1", api_login_id: "old_login", transaction_key: "old_key")
      end

      it "keeps obfuscated secrets and updates the others" do
        result = authorize_net_service.create_or_update(
          organization:,
          id: existing_provider.id,
          code: "authorize_net_1",
          name: "Renamed",
          api_login_id: "••••••••…gin",
          transaction_key: "new_key"
        )

        expect(result).to be_success
        expect(result.authorize_net_provider).to have_attributes(
          id: existing_provider.id,
          name: "Renamed",
          api_login_id: "old_login",
          transaction_key: "new_key"
        )
      end

      context "when the code changes" do
        let(:customer) { create(:customer, organization:, payment_provider: "authorize_net", payment_provider_code: "authorize_net_1") }

        before { create(:authorize_net_customer, customer:, payment_provider: existing_provider) }

        it "updates the code on linked customers" do
          authorize_net_service.create_or_update(organization:, id: existing_provider.id, code: "authorize_net_2")

          expect(customer.reload.payment_provider_code).to eq("authorize_net_2")
        end
      end
    end
  end
end
