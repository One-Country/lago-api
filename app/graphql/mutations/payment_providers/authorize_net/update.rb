# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module AuthorizeNet
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateAuthorizeNetPaymentProvider"
        description "Update Authorize.net payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::AuthorizeNet
      end
    end
  end
end
