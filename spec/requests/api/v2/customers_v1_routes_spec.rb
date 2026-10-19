# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 customer routes served by v1 controllers" do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment_method) { create(:payment_method, customer:, organization:, is_default: false) }
  let(:payment) { create(:payment, payable: create(:invoice, organization:, customer:), customer:) }

  before { payment }

  it "lists the payments of the customer" do
    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payments")

    expect(response).to have_http_status(:success)
    expect(json[:payments].map { it[:lago_id] }).to eq([payment.id])
  end

  it "lists the payment methods of the customer" do
    payment_method

    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods")

    expect(response).to have_http_status(:success)
    expect(json[:payment_methods].map { it[:lago_id] }).to eq([payment_method.id])
  end

  it "sets a payment method as default" do
    put_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods/#{payment_method.id}/set_as_default")

    expect(response).to have_http_status(:success)
    expect(json[:payment_method]).to include(lago_id: payment_method.id, is_default: true)
  end

  it "deletes a payment method" do
    delete_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods/#{payment_method.id}")

    expect(response).to have_http_status(:success)
    expect(json[:payment_method][:lago_id]).to eq(payment_method.id)
    expect(payment_method.reload).to be_discarded
  end

  context "with a Stripe customer" do
    let(:stripe_provider) { create(:stripe_provider, organization:) }

    before do
      create(:stripe_customer, customer_id: customer.id, payment_provider: stripe_provider)
      customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    it "generates a checkout url" do
      post_with_token(organization, "/api/v2/customers/#{customer.external_id}/checkout_url")

      expect(response).to have_http_status(:success)
      expect(json[:customer][:checkout_url]).to eq("https://example.com")
    end
  end
end
