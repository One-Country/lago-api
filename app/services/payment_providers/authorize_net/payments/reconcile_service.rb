# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Payments
      # A payment answered as a duplicate whose earlier transaction could not
      # be found yet is kept processing. This looks it up again and settles it
      # with that transaction's outcome; it does nothing while still not found.
      class ReconcileService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment

          super
        end

        def call
          result.payment = payment
          return result unless payment.payable_payment_status == "processing" && payment.provider_payment_id.blank?

          lookup = Transactions::FindByInvoiceNumberService.call!(
            payment_provider: payment.payment_provider,
            invoice_number: CreateService.invoice_number(payment)
          )
          return result unless lookup.transaction

          status = CreateService::LISTED_STATUSES.fetch(lookup.transaction["transactionStatus"], "held_for_review")
          payment.update!(provider_payment_id: lookup.transaction["transId"].to_s)

          status_service.call!(:update_payment_status, payment:, status:)
          result
        end

        private

        attr_reader :payment

        def status_service
          payment.payable.is_a?(PaymentRequest) ? PaymentRequests::Payments::AuthorizeNetService : Invoices::Payments::AuthorizeNetService
        end
      end
    end
  end
end
