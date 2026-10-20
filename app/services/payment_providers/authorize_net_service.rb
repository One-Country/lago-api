# frozen_string_literal: true

module PaymentProviders
  class AuthorizeNetService < BaseService
    Result = BaseResult[:authorize_net_provider]

    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "authorize_net"
      )

      authorize_net_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::AuthorizeNetProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = authorize_net_provider.code

      %i[api_login_id transaction_key signature_key].each do |secret|
        next unless args.key?(secret)
        next if Types::ObfuscatedStringType.obfuscated?(args[secret])

        authorize_net_provider.public_send(:"#{secret}=", args[secret])
      end
      authorize_net_provider.environment = args[:environment] if args.key?(:environment)
      authorize_net_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      authorize_net_provider.code = args[:code] if args.key?(:code)
      authorize_net_provider.name = args[:name] if args.key?(:name)
      authorize_net_provider.save!

      if payment_provider_code_changed?(authorize_net_provider, old_code, args)
        authorize_net_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.authorize_net_provider = authorize_net_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
