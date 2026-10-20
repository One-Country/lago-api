# frozen_string_literal: true

module PaymentRequests
  module Payments
    class AuthorizeNetService < BaseService
      include Updatable
      include TypedResults

      RESULTS = {
        update_payment_status: BaseResult[:payment, :payable]
      }.freeze

      private

      attr_reader :payable

      delegate :customer, to: :payable

      # Settles a payment whose outcome arrived after the charge, such as a
      # transaction held for review and later approved or declined.
      def update_payment_status(payment:, status:)
        @payable = payment.payable
        result.payment = payment
        result.payable = payable
        return result if payable.payment_succeeded?

        payment.status = status
        payable_payment_status = payment.payment_provider.determine_payment_status(payment.status)
        payment.payable_payment_status = payable_payment_status
        payment.save!

        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)
        update_invoices_paid_amount_cents(payment_status: payable_payment_status)
        reset_customer_dunning_campaign_status(payable_payment_status)

        PaymentRequestMailer.with(payment_request: payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def update_payable_payment_status(payment_status:)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
            ready_for_payment_processing: !payment_status_succeeded?(payment_status)
          },
          webhook_notification: true
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:)
        result.payable.invoices.each do |invoice|
          next if invoice.payment_succeeded? && !payment_status_succeeded?(payment_status)

          Invoices::UpdateService.call(
            invoice:,
            params: {
              payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
              ready_for_payment_processing: !payment_status_succeeded?(payment_status)
            },
            webhook_notification: true
          ).raise_if_error!
        end
      end

      def payment_status_succeeded?(payment_status)
        payment_status.to_sym == :succeeded
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status_succeeded?(payment_status)
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign_for_currency!(payable.currency)
      end
    end
  end
end
