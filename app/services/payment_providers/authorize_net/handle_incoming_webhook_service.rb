# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult[:event]

      def initialize(inbound_webhook:)
        @inbound_webhook = inbound_webhook

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id: inbound_webhook.organization_id,
          code: inbound_webhook.code,
          payment_provider_type: "authorize_net"
        )
        return result.service_failure!(code: "webhook_error", message: payment_provider_result.error.message) unless payment_provider_result.success?

        event = JSON.parse(inbound_webhook.payload)

        HandleEventService.call!(payment_provider: payment_provider_result.payment_provider, event:)

        result.event = event
        result
      rescue JSON::ParserError
        result.service_failure!(code: "webhook_error", message: "Invalid payload")
      end

      private

      attr_reader :inbound_webhook
    end
  end
end
