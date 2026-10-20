# frozen_string_literal: true

module Types
  module PaymentProviders
    class AuthorizeNetInput < BaseInputObject
      description "Authorize.net input arguments"

      argument :api_login_id, String, required: true
      argument :code, String, required: true
      argument :environment, Types::PaymentProviders::AuthorizeNetEnvironmentEnum, required: true
      argument :name, String, required: true
      argument :signature_key, String, required: false
      argument :success_redirect_url, String, required: false
      argument :transaction_key, String, required: true
    end
  end
end
