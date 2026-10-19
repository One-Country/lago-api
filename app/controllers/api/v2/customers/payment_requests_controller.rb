# frozen_string_literal: true

module Api
  module V2
    module Customers
      class PaymentRequestsController < ::Api::V1::Customers::PaymentRequestsController
        def index
          payment_request_index(external_customer_id: customer.external_id, serializer: ::V2::PaymentRequestSerializer)
        end
      end
    end
  end
end
