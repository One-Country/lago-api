# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Customers
      class SyncPaymentMethodsJob < ApplicationJob
        queue_as :providers

        unique :until_executing, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 5
        retry_on BaseService::LockAcquisitionFailure, ActiveRecord::Deadlocked, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

        def perform(provider_customer)
          PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsService.call!(provider_customer:)
        end
      end
    end
  end
end
