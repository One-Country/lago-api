# frozen_string_literal: true

module V2
  class PaymentRequestSerializer < ::V1::PaymentRequestSerializer
    private

    def invoices
      {
        invoices: model.invoices.map do |invoice|
          serializer = invoice.product_catalog? ? ::V2::InvoiceSerializer : ::V1::InvoiceSerializer
          serializer.new(invoice).serialize
        end
      }
    end
  end
end
