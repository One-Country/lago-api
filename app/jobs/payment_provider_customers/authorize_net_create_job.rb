# frozen_string_literal: true

module PaymentProviderCustomers
  class AuthorizeNetCreateJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(authorize_net_customer)
      PaymentProviderCustomers::AuthorizeNetService.call!(:create, authorize_net_customer)
    end
  end
end
