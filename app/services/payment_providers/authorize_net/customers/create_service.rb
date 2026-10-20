# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Customers
      class CreateService < BaseService
        Result = BaseResult[:provider_customer]

        def initialize(customer:, payment_provider_id:, params:, async: true)
          @customer = customer
          @payment_provider_id = payment_provider_id
          @params = params || {}
          @async = async

          super
        end

        def call
          provider_customer = PaymentProviderCustomers::AuthorizeNetCustomer.find_by(customer_id: customer.id)
          provider_customer ||= PaymentProviderCustomers::AuthorizeNetCustomer.new(
            customer_id: customer.id,
            payment_provider_id:,
            organization_id: organization.id
          )

          if params.key?(:provider_customer_id)
            provider_customer.provider_customer_id = params[:provider_customer_id].presence
          end

          if params.key?(:sync_with_provider)
            provider_customer.sync_with_provider = params[:sync_with_provider].presence
          end

          provider_customer.save!

          result.provider_customer = provider_customer

          if should_create_provider_customer?
            create_customer_on_provider_service(async)
          elsif should_sync_payment_methods?
            SyncPaymentMethodsJob.perform_after_commit(provider_customer)
          end

          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_accessor :customer, :payment_provider_id, :params, :async

        delegate :organization, to: :customer

        def create_customer_on_provider_service(async)
          return PaymentProviderCustomers::AuthorizeNetCreateJob.perform_after_commit(result.provider_customer) if async

          PaymentProviderCustomers::AuthorizeNetCreateJob.perform_now(result.provider_customer)
        end

        def should_create_provider_customer?
          # NOTE: the customer does not exists on the service provider
          # and the customer id was not removed from the customer
          # customer sync with provider setting is set to true
          !result.provider_customer.provider_customer_id? &&
            !result.provider_customer.provider_customer_id_previously_changed? &&
            result.provider_customer.sync_with_provider.present?
        end

        # NOTE: An existing customer profile was linked: its payment profiles
        #       become the customer's payment methods.
        def should_sync_payment_methods?
          result.provider_customer.provider_customer_id? &&
            (result.provider_customer.provider_customer_id_previously_changed? || customer.payment_methods.empty?)
        end
      end
    end
  end
end
