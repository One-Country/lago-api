# frozen_string_literal: true

module PaymentProviders
  module AuthorizeNet
    module Customers
      # Mirrors the payment profiles of an Authorize.net customer profile as
      # payment methods. As with every provider, a new payment method becomes
      # the default. Authorize.net's default profile is synced last, so it is
      # the default after a first sync.
      class SyncPaymentMethodsService < BaseService
        Result = BaseResult[:payment_methods]

        def initialize(provider_customer:)
          @provider_customer = provider_customer

          super
        end

        def call
          result.payment_methods = []
          return result unless provider_customer.provider_customer_id?

          response = Client.new(provider_customer.payment_provider).call(
            "getCustomerProfileRequest",
            {customerProfileId: provider_customer.provider_customer_id, unmaskExpirationDate: true},
            retry_transient_errors: true
          )
          return result.service_failure!(code: response.message_code, message: response.message_text) unless response.ok?

          payment_profiles = Array(response.dig("profile", "paymentProfiles"))
            .sort_by { |payment_profile| payment_profile["defaultPaymentProfile"] ? 1 : 0 }
          result.payment_methods = payment_profiles.map { |payment_profile| sync(payment_profile) }

          remove_missing_payment_methods
          set_default(payment_profiles)

          result
        end

        private

        attr_reader :provider_customer

        delegate :customer, to: :provider_customer

        def sync(payment_profile)
          payment_method = PaymentMethods::FindOrCreateFromProviderService.call!(
            customer:,
            payment_provider_customer: provider_customer,
            provider_method_id: payment_profile["customerPaymentProfileId"].to_s,
            params: {provider_payment_methods: %w[card], details: card_details(payment_profile)}
          ).payment_method

          PaymentMethods::UpdateDetailsService.call!(payment_method:, insert: card_details(payment_profile))
          payment_method
        end

        def remove_missing_payment_methods
          synced_ids = result.payment_methods.map(&:id)

          provider_customer.payment_methods.where.not(id: synced_ids).order(:created_at).each do |payment_method|
            PaymentMethods::DestroyService.call!(payment_method:)
          end
        end

        def set_default(payment_profiles)
          return if result.payment_methods.empty?
          return if customer.payment_methods.where(is_default: true).exists?

          default_profile_id = payment_profiles.find { |payment_profile| payment_profile["defaultPaymentProfile"] }&.dig("customerPaymentProfileId")
          payment_method = result.payment_methods.find { |method| method.provider_method_id == default_profile_id.to_s } ||
            result.payment_methods.first

          PaymentMethods::SetAsDefaultService.call!(payment_method:)
        end

        # cardNumber is masked ("XXXX1111"); expirationDate is "YYYY-MM" when unmasked.
        def card_details(payment_profile)
          card = payment_profile.dig("payment", "creditCard") || {}
          year, month = card["expirationDate"].to_s.split("-")

          PaymentMethods::CardDetails.new(
            type: "card",
            last4: card["cardNumber"].to_s.last(4).presence,
            brand: card["cardType"]&.downcase,
            expiration_month: month&.to_i,
            expiration_year: year&.to_i,
            card_holder_name: nil,
            issuer: nil
          ).to_h
        end
      end
    end
  end
end
