# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module AuthorizeNet
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddAuthorizeNetPaymentProvider"
        description "Add Authorize.net payment provider"

        input_object_class Types::PaymentProviders::AuthorizeNetInput

        type Types::PaymentProviders::AuthorizeNet
      end
    end
  end
end
