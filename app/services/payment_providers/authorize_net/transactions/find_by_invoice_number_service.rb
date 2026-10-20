# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Transactions
      # Finds the transaction an earlier attempt of a payment created, by the
      # invoice number every charge carries. Authorize.net has no idempotency
      # keys: when a retried charge is rejected as a duplicate, this is how we
      # learn what the first attempt did. Only unsettled transactions are
      # searched, which covers the duplicate window of a retried job.
      class FindByInvoiceNumberService < BaseService
        Result = BaseResult[:transaction]

        PAGE_SIZE = 1000

        def initialize(payment_provider:, invoice_number:)
          @payment_provider = payment_provider
          @invoice_number = invoice_number

          super
        end

        def call
          response = Client.new(payment_provider).call(
            "getUnsettledTransactionListRequest",
            {
              sorting: {orderBy: "submitTimeUTC", orderDescending: true},
              paging: {limit: PAGE_SIZE, offset: 1}
            },
            retry_transient_errors: true
          )
          return result.service_failure!(code: response.message_code, message: response.message_text) unless response.ok?

          result.transaction = Array(response["transactions"]).find { |transaction| transaction["invoiceNumber"] == invoice_number }
          result
        end

        private

        attr_reader :payment_provider, :invoice_number
      end
    end
  end
end
