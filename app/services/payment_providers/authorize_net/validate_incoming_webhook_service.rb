# frozen_string_literal: true

require "openssl"

module PaymentProviders
  module AuthorizeNet
    # X-ANET-Signature is "sha512=<hex HMAC-SHA512 of the raw body>", keyed
    # with the signature key from the merchant interface.
    class ValidateIncomingWebhookService < BaseService
      SIGNATURE_FORMAT = /\Asha512=(?<digest>[0-9a-f]+)\z/i

      def initialize(payload:, signature:, payment_provider:)
        @payload = payload
        @signature = signature
        @provider = payment_provider

        super
      end

      def call
        digest = SIGNATURE_FORMAT.match(signature.to_s.strip)&.[](:digest)
        return invalid_signature if digest.nil? || provider.signature_key.blank?

        expected = OpenSSL::HMAC.hexdigest("SHA512", provider.signature_key, payload.to_s)
        return invalid_signature unless ActiveSupport::SecurityUtils.secure_compare(expected, digest.downcase)

        result
      end

      private

      attr_reader :payload, :signature, :provider

      def invalid_signature
        result.service_failure!(code: "webhook_error", message: "Invalid signature")
      end
    end
  end
end
