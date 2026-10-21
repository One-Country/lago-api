# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    # Authorize.net webhook events. Events about transactions or profiles Lago
    # does not know (charges made outside Lago on the same account) are ignored.
    class HandleEventService < BaseService
      Result = BaseResult[:payment, :provider_customer]

      HELD_PAYMENT_OUTCOMES = {
        "net.authorize.payment.fraud.approved" => "approved",
        "net.authorize.payment.fraud.declined" => "declined"
      }.freeze

      PAYMENT_PROFILE_EVENTS = %w[
        net.authorize.customer.paymentProfile.created
        net.authorize.customer.paymentProfile.updated
        net.authorize.customer.paymentProfile.deleted
      ].freeze

      def initialize(payment_provider:, event:)
        @payment_provider = payment_provider
        @event = event

        super
      end

      def call
        if HELD_PAYMENT_OUTCOMES.key?(event_type)
          settle_held_payment
        elsif PAYMENT_PROFILE_EVENTS.include?(event_type)
          sync_payment_methods
        end

        result
      end

      private

      attr_reader :payment_provider, :event

      def event_type
        event["eventType"]
      end

      def payload
        event["payload"] || {}
      end

      def settle_held_payment
        payment = payment_provider.payments.find_by(provider_payment_id: payload["id"].to_s)
        return unless payment

        result.payment = payment
        status_service(payment).call!(:update_payment_status, payment:, status: HELD_PAYMENT_OUTCOMES.fetch(event_type))
      end

      def status_service(payment)
        payment.payable.is_a?(PaymentRequest) ? PaymentRequests::Payments::AuthorizeNetService : Invoices::Payments::AuthorizeNetService
      end

      def sync_payment_methods
        provider_customer = payment_provider.payment_provider_customers
          .find_by(provider_customer_id: payload["customerProfileId"].to_s)
        return unless provider_customer

        result.provider_customer = provider_customer
        Customers::SyncPaymentMethodsJob.perform_later(provider_customer)
      end
    end
  end
end
