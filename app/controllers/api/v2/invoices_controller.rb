# frozen_string_literal: true

module Api
  module V2
    class InvoicesController < BaseController
      include Api::V2::InvoiceIndex

      def index
        invoice_index
      end

      def show
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        render_invoice(invoice)
      end

      def void
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::VoidService.call(invoice:, params: params.permit(:generate_credit_note, :refund_amount, :credit_amount))

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def download_pdf
        invoice = find_invoice(:finalized)
        return not_found_error(resource: "invoice") unless invoice

        if invoice.file.present?
          return render(json: ::V2::InvoiceSerializer.new(invoice, root_name: "invoice"))
        end

        ::Invoices::GeneratePdfJob.perform_later(invoice)

        head(:ok)
      end

      def resend_email
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Emails::ResendService.call(
          resource: invoice,
          to: resend_email_params[:to],
          cc: resend_email_params[:cc],
          bcc: resend_email_params[:bcc]
        )

        if result.success?
          head(:ok)
        else
          render_error_response(result)
        end
      end

      def retry
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::RetryService.call(invoice:)

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      private

      def find_invoice(status_scope)
        current_organization.invoices.public_send(status_scope).product_catalog.find_by(id: params[:id])
      end

      def resend_email_params
        params.permit(to: [], cc: [], bcc: [])
      end

      def render_invoice(invoice)
        render(
          json: ::V2::InvoiceSerializer.new(
            invoice,
            root_name: "invoice",
            includes: ::V2::InvoiceSerializer::DETAIL_INCLUDES
          )
        )
      end

      def resource_name
        "invoice"
      end
    end
  end
end
