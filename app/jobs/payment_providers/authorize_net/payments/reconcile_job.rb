# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Payments
      class ReconcileJob < ApplicationJob
        queue_as :providers

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 5

        def perform(payment)
          PaymentProviders::AuthorizeNet::Payments::ReconcileService.call!(payment:)
        end
      end
    end
  end
end
