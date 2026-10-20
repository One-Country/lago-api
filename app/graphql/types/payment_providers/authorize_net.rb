# frozen_string_literal: true

module Types
  module PaymentProviders
    class AuthorizeNet < Types::BaseObject
      graphql_name "AuthorizeNetProvider"

      field :api_login_id, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :code, String, null: false
      field :environment, Types::PaymentProviders::AuthorizeNetEnvironmentEnum, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :signature_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
      field :transaction_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
    end
  end
end
