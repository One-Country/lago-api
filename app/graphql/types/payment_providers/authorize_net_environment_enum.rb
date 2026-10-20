# frozen_string_literal: true

module Types
  module PaymentProviders
    class AuthorizeNetEnvironmentEnum < Types::BaseEnum
      ::PaymentProviders::AuthorizeNetProvider::ENVIRONMENTS.each do |environment|
        value environment
      end
    end
  end
end
