# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::Customers::CreateService do
  subject(:result) { described_class.call(customer:, payment_provider_id: authorize_net_provider.id, params:, async: true) }

  let_it_be(:organization) { create(:organization) }

  let(:customer) { create(:customer, organization:) }
  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }

  context "when linking an existing customer profile" do
    let(:params) { {provider_customer_id: "519123456"} }

    it "saves the profile and syncs its payment profiles" do
      expect(result).to be_success
      expect(result.provider_customer).to have_attributes(
        type: "PaymentProviderCustomers::AuthorizeNetCustomer",
        provider_customer_id: "519123456",
        payment_provider_id: authorize_net_provider.id
      )
      expect(PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsJob).to have_been_enqueued.with(result.provider_customer)
      expect(PaymentProviderCustomers::AuthorizeNetCreateJob).not_to have_been_enqueued
    end
  end

  context "when asked to create the customer profile on Authorize.net" do
    let(:params) { {sync_with_provider: true} }

    it "enqueues the profile creation" do
      expect(result).to be_success
      expect(PaymentProviderCustomers::AuthorizeNetCreateJob).to have_been_enqueued.with(result.provider_customer)
      expect(PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsJob).not_to have_been_enqueued
    end
  end

  context "when the linked profile is unchanged and payment methods exist" do
    let(:params) { {provider_customer_id: "519123456"} }

    before do
      provider_customer = create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: "519123456")
      create(:payment_method, customer:, payment_provider_customer: provider_customer)
    end

    it "does not sync again" do
      expect(result).to be_success
      expect(PaymentProviders::AuthorizeNet::Customers::SyncPaymentMethodsJob).not_to have_been_enqueued
    end
  end
end
