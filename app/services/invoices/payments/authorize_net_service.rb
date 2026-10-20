# frozen_string_literal: true

module Invoices
  module Payments
    class AuthorizeNetService < BaseService
      include TypedResults

      RESULTS = {
        update_payment_status: BaseResult[:payment, :invoice]
      }.freeze

      private

      # Settles a payment whose outcome arrived after the charge, such as a
      # transaction held for review and later approved or declined.
      def update_payment_status(payment:, status:)
        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.status = status
        payable_payment_status = payment.payment_provider.determine_payment_status(payment.status)
        payment.payable_payment_status = payable_payment_status
        payment.save!

        deliver_webhook if payable_payment_status.to_sym == :succeeded
        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        update_invoice_payment_status(payment_status: payable_payment_status)

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def update_invoice_payment_status(payment_status:)
        params = {
          payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
          ready_for_payment_processing: payment_status.to_sym != :succeeded
        }

        if payment_status.to_sym == :succeeded
          params[:total_paid_amount_cents] = result.invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
        end

        Invoices::UpdateService.call(
          invoice: result.invoice,
          params:,
          webhook_notification: true
        ).raise_if_error!
      end

      def deliver_webhook
        SendWebhookJob.perform_later("payment.succeeded", result.payment)
      end
    end
  end
end
