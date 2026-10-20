# frozen_string_literal: true

module PaymentProviders
  class AuthorizeNetProvider < BaseProvider
    ENVIRONMENTS = %w[sandbox production].freeze

    API_URLS = {
      "sandbox" => "https://apitest.authorize.net/xml/v1/request.api",
      "production" => "https://api.authorize.net/xml/v1/request.api"
    }.freeze

    # Payment#status values, named after the transaction's response code
    # (1 approved, 2 declined, 3 error, 4 held for review).
    PROCESSING_STATUSES = %w[held_for_review].freeze
    SUCCESS_STATUSES = %w[approved].freeze
    FAILED_STATUSES = %w[declined error].freeze

    RESPONSE_CODE_STATUSES = {
      "1" => "approved",
      "2" => "declined",
      "3" => "error",
      "4" => "held_for_review"
    }.freeze

    validates :api_login_id, presence: true
    validates :transaction_key, presence: true
    validates :environment, inclusion: {in: ENVIRONMENTS}

    secrets_accessors :api_login_id, :transaction_key, :signature_key
    settings_accessors :environment

    def api_url
      API_URLS.fetch(environment)
    end

    def webhook_end_point
      URI.join(
        ENV["LAGO_API_URL"],
        "webhooks/authorize_net/#{organization_id}?code=#{URI.encode_www_form_component(code)}"
      )
    end

    def payment_type
      "authorize_net"
    end
  end
end

# == Schema Information
#
# Table name: payment_providers
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_payment_providers_on_code_and_organization_id  (code,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_payment_providers_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
