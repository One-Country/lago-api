# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    # Authorize.net's JSON API: one endpoint, the request named by the body's
    # root key. It answers 200 even for errors, which come back in `messages`.
    # Its JSON follows the XML schema, so the order of keys in a request matters.
    class Client
      READ_TIMEOUT = 30

      def initialize(payment_provider)
        @payment_provider = payment_provider
      end

      # `retry_transient_errors` must stay false for requests that move money:
      # a timed out charge may still have reached Authorize.net.
      def call(request_name, body, retry_transient_errors: false)
        payload = {
          request_name => {
            merchantAuthentication: {
              name: payment_provider.api_login_id,
              transactionKey: payment_provider.transaction_key
            }
          }.merge(body)
        }

        response = http_client(retry_transient_errors).post_with_response(payload, {})
        # NOTE: The body is binary and starts with a UTF-8 byte order mark.
        Response.new(JSON.parse(response.body.to_s.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")))
      end

      class Response
        attr_reader :body

        def initialize(body)
          @body = body
        end

        def ok?
          body.dig("messages", "resultCode") == "Ok"
        end

        def message_code
          body.dig("messages", "message", 0, "code")
        end

        def message_text
          body.dig("messages", "message", 0, "text")
        end

        delegate :[], to: :body

        def dig(...)
          body.dig(...)
        end
      end

      private

      attr_reader :payment_provider

      def http_client(retry_transient_errors)
        LagoHttpClient::Client.new(
          payment_provider.api_url,
          read_timeout: READ_TIMEOUT,
          retry_on_transient_errors: retry_transient_errors
        )
      end
    end
  end
end
