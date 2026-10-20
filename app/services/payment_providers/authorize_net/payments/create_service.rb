# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Payments
      # Charges a payment on the customer's stored payment profile (CIM), as a
      # merchant-initiated charge on a stored credential.
      class CreateService < BaseService
        Result = BaseResult[:payment, :error_message, :error_code, :reraise, :should_retry]

        # Authorize.net rejects a transaction with the same amount, card and
        # invoice number inside this window (8 hours, its maximum). A retried
        # job for the same payment reuses its invoice number, so a charge that
        # timed out is answered as a duplicate instead of being made twice.
        DUPLICATE_WINDOW_SECONDS = 28_800
        DUPLICATE_REASON_CODE = "11"
        INVOICE_NUMBER_LENGTH = 20
        DESCRIPTION_LENGTH = 255

        # Statuses of an earlier transaction found after a duplicate response.
        LISTED_STATUSES = {
          "authorizedPendingCapture" => "approved",
          "capturedPendingSettlement" => "approved",
          "settledSuccessfully" => "approved",
          "FDSPendingReview" => "held_for_review",
          "FDSAuthorizedPendingReview" => "held_for_review",
          "declined" => "declined"
        }.freeze

        TRANSIENT_ERRORS = LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @payable = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          payment_profile_id = payment.payment_method&.provider_method_id
          return prepare_failed_result(error_code: "missing_payment_method", error_message: "No payment profile to charge") unless payment_profile_id

          # The payable has been settled by another payment path
          raise ::Invoices::Payments::AlreadyPaidError if payable.reload.payment_succeeded?

          response = client.call("createTransactionRequest", transaction_payload(payment_profile_id))
          transaction = response["transactionResponse"]

          if transaction.blank? || transaction["responseCode"].blank?
            return prepare_failed_result(error_code: response.message_code, error_message: response.message_text)
          end

          return handle_duplicate if transaction_error_code(transaction) == DUPLICATE_REASON_CODE

          apply_transaction(
            transaction_id: transaction["transId"],
            status: AuthorizeNetProvider::RESPONSE_CODE_STATUSES.fetch(transaction["responseCode"], "error"),
            error_code: transaction_error_code(transaction),
            error_message: transaction.dig("errors", 0, "errorText")
          )
        rescue LagoHttpClient::HttpError, *TRANSIENT_ERRORS => e
          # NOTE: The charge may have reached Authorize.net. The job retries with
          #       the same invoice number, which the duplicate window catches.
          raise ::Invoices::Payments::ConnectionError, e
        end

        private

        attr_reader :payment, :reference, :metadata, :payable, :provider_customer

        delegate :payment_provider, to: :provider_customer

        def client
          @client ||= Client.new(payment_provider)
        end

        def invoice_number
          @invoice_number ||= Digest::SHA256.hexdigest("lago-payment-#{payment.id}").first(INVOICE_NUMBER_LENGTH)
        end

        # Keys follow the order of Authorize.net's XML schema.
        def transaction_payload(payment_profile_id)
          {
            refId: invoice_number,
            transactionRequest: {
              transactionType: "authCaptureTransaction",
              amount: format("%.2f", Money.from_cents(payment.amount_cents, payment.amount_currency).to_d),
              profile: {
                customerProfileId: provider_customer.provider_customer_id,
                paymentProfile: {paymentProfileId: payment_profile_id}
              },
              order: {
                invoiceNumber: invoice_number,
                description: reference.to_s.first(DESCRIPTION_LENGTH)
              },
              transactionSettings: {
                setting: [{settingName: "duplicateWindow", settingValue: DUPLICATE_WINDOW_SECONDS.to_s}]
              },
              processingOptions: {isSubsequentAuth: true}
            }
          }
        end

        def transaction_error_code(transaction)
          transaction.dig("errors", 0, "errorCode")
        end

        def handle_duplicate
          lookup = Transactions::FindByInvoiceNumberService.call(payment_provider:, invoice_number:)
          earlier = lookup.transaction if lookup.success?

          if earlier.nil?
            # NOTE: An earlier attempt was sent but can't be found. Keep the payment
            #       processing so nothing charges again until it is reconciled.
            return apply_transaction(transaction_id: nil, status: "held_for_review", error_code: DUPLICATE_REASON_CODE)
          end

          apply_transaction(
            transaction_id: earlier["transId"],
            status: LISTED_STATUSES.fetch(earlier["transactionStatus"], "error"),
            error_code: (DUPLICATE_REASON_CODE unless LISTED_STATUSES[earlier["transactionStatus"]] == "approved")
          )
        end

        def apply_transaction(transaction_id:, status:, error_code: nil, error_message: nil)
          payable_payment_status = payment_provider.determine_payment_status(status)

          if payable_payment_status == :failed
            return prepare_failed_result(transaction_id:, status:, error_code:, error_message:)
          end

          payment.provider_payment_id = transaction_id if transaction_id.present? && transaction_id != "0"
          payment.status = status
          payment.payable_payment_status = payable_payment_status
          payment.error_code = error_code
          payment.save!

          result.payment = payment
          result
        end

        def prepare_failed_result(error_code:, error_message:, transaction_id: nil, status: "error")
          result.error_message = error_message
          result.error_code = error_code
          result.reraise = false
          result.should_retry = false

          payment.update!(
            status:,
            payable_payment_status: :failed,
            provider_payment_id: (transaction_id if transaction_id.present? && transaction_id != "0"),
            error_code:
          )

          result.service_failure!(code: "authorize_net_error", message: "#{error_code}: #{error_message}")
        end
      end
    end
  end
end
