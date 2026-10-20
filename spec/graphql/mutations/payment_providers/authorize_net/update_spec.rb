# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::AuthorizeNet::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:membership) { create(:membership) }
  let(:authorize_net_provider) { create(:authorize_net_provider, organization: membership.organization) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAuthorizeNetPaymentProviderInput!) {
        updateAuthorizeNetPaymentProvider(input: $input) {
          id,
          code,
          name,
          successRedirectUrl
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates the Authorize.net provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {input: {
        id: authorize_net_provider.id,
        code: "authorize_net_2",
        name: "Authorize.net 2",
        successRedirectUrl: "https://example.com/done"
      }}
    )

    expect(result["data"]["updateAuthorizeNetPaymentProvider"]).to eq(
      "id" => authorize_net_provider.id,
      "code" => "authorize_net_2",
      "name" => "Authorize.net 2",
      "successRedirectUrl" => "https://example.com/done"
    )
  end
end
