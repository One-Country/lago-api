# frozen_string_literal: true

module PaymentProviderCustomers
  class AuthorizeNetService < BaseService
    include TypedResults

    RESULTS = {
      create: BaseResult[:authorize_net_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult[:checkout_url]
    }.freeze

    # Authorize.net limits merchantCustomerId to 20 characters.
    MERCHANT_CUSTOMER_ID_LENGTH = 20
    DUPLICATE_PROFILE_CODE = "E00039"

    private

    attr_accessor :authorize_net_customer

    delegate :customer, to: :authorize_net_customer

    def create(authorize_net_customer)
      @authorize_net_customer = authorize_net_customer
      result.authorize_net_customer = authorize_net_customer
      return result if authorize_net_customer.provider_customer_id?

      response = PaymentProviders::AuthorizeNet::Client.new(authorize_net_customer.payment_provider).call(
        "createCustomerProfileRequest",
        {profile: profile_params}
      )

      provider_customer_id = response["customerProfileId"].presence || duplicate_profile_id(response)
      return deliver_error_webhook(response) if provider_customer_id.blank?

      authorize_net_customer.update!(provider_customer_id:)
      deliver_success_webhook

      result
    rescue LagoHttpClient::HttpError => e
      deliver_error_webhook(e)
    end

    def update(authorize_net_customer)
      @authorize_net_customer = authorize_net_customer
      result
    end

    # NOTE: Authorize.net payment profiles are created by the merchant's own
    #       checkout (Accept.js, wallets) and synced back; Lago has no hosted page.
    def generate_checkout_url(authorize_net_customer, send_webhook: true)
      @authorize_net_customer = authorize_net_customer
      result.single_validation_failure!(error_code: "checkout_url_not_supported")
    end

    # Keys follow the order of Authorize.net's XML schema.
    def profile_params
      {
        merchantCustomerId: customer.external_id.to_s.first(MERCHANT_CUSTOMER_ID_LENGTH),
        description: customer.name.presence&.first(255),
        email: customer.email.to_s.split(",").first&.strip.presence
      }.compact
    end

    # "A duplicate record with ID 1234 already exists." The profile already
    # exists for this merchantCustomerId, so it is linked instead.
    def duplicate_profile_id(response)
      return unless response.message_code == DUPLICATE_PROFILE_CODE

      response.message_text.to_s[/ID (\d+)/, 1]
    end

    def deliver_success_webhook
      SendWebhookJob.perform_later("customer.payment_provider_created", customer)
    end

    def deliver_error_webhook(error)
      message, error_code = if error.is_a?(PaymentProviders::AuthorizeNet::Client::Response)
        [error.message_text, error.message_code]
      else
        [error.message, error.error_code]
      end

      SendWebhookJob.perform_later(
        "customer.payment_provider_error",
        customer,
        provider_error: {message:, error_code:}
      )

      result.service_failure!(code: "authorize_net_error", message: "#{error_code}: #{message}")
    end
  end
end
