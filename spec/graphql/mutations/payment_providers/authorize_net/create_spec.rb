# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::AuthorizeNet::Create do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddAuthorizeNetPaymentProviderInput!) {
        addAuthorizeNetPaymentProvider(input: $input) {
          id,
          code,
          name,
          environment,
          apiLoginId,
          transactionKey,
          signatureKey,
          successRedirectUrl
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates an Authorize.net provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      # `view` is necessary to retrieve the created record in the response
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {input: {
        code: "authorize_net_1",
        name: "Authorize.net",
        environment: "sandbox",
        apiLoginId: "5KP3u95bQpv",
        transactionKey: "346HZ32z3fP4hTG2",
        signatureKey: "56E529FB8ABC",
        successRedirectUrl: "https://example.com/success"
      }}
    )

    expect(result["data"]["addAuthorizeNetPaymentProvider"]).to eq(
      "id" => PaymentProviders::AuthorizeNetProvider.last.id,
      "code" => "authorize_net_1",
      "name" => "Authorize.net",
      "environment" => "sandbox",
      "apiLoginId" => "••••••••…Qpv",
      "transactionKey" => "••••••••…TG2",
      "signatureKey" => "••••••••…ABC",
      "successRedirectUrl" => "https://example.com/success"
    )
  end
end
