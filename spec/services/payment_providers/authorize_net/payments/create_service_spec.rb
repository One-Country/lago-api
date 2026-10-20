# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AuthorizeNet::Payments::CreateService do
  subject(:result) { described_class.call(payment:, reference:, metadata: {}) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:authorize_net_provider) { create(:authorize_net_provider, organization:) }
  let(:authorize_net_customer) do
    create(:authorize_net_customer, customer:, payment_provider: authorize_net_provider, provider_customer_id: "519123456")
  end
  let(:payment_method) do
    create(:payment_method, customer:, payment_provider_customer: authorize_net_customer, provider_method_id: "527123456")
  end
  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription, total_amount_cents: 2500, currency: "USD") }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider: authorize_net_provider,
      payment_provider_customer: authorize_net_customer,
      payment_method:,
      provider_payment_id: nil,
      amount_cents: 2500,
      amount_currency: "USD",
      status: "pending",
      payable_payment_status: "pending"
    )
  end
  let(:reference) { "#{invoice.billing_entity.name} - Invoice #{invoice.number}" }
  let(:invoice_number) { Digest::SHA256.hexdigest("lago-payment-#{payment.id}").first(20) }
  let(:api_url) { "https://apitest.authorize.net/xml/v1/request.api" }
  let(:transaction_fixture) { "create_transaction_approved.json" }

  def fixture(name)
    File.read(Rails.root.join("spec/fixtures/authorize_net", name))
  end

  before do
    stub_request(:post, api_url)
      .with(body: hash_including("createTransactionRequest"))
      .to_return(status: 200, body: "\uFEFF#{fixture(transaction_fixture)}".b)
  end

  context "when the charge is approved" do
    it "marks the payment succeeded with the transaction ID" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(
        provider_payment_id: "80042512345",
        status: "approved",
        payable_payment_status: "succeeded"
      )
    end

    it "charges the payment profile as a subsequent authorization" do
      result

      expect(WebMock).to(have_requested(:post, api_url).with do |request|
        body = JSON.parse(request.body)
        transaction_request = body.dig("createTransactionRequest", "transactionRequest")

        expect(body["createTransactionRequest"].keys).to eq(%w[merchantAuthentication refId transactionRequest])
        expect(body.dig("createTransactionRequest", "merchantAuthentication")).to eq(
          "name" => authorize_net_provider.api_login_id,
          "transactionKey" => authorize_net_provider.transaction_key
        )
        expect(transaction_request).to eq(
          "transactionType" => "authCaptureTransaction",
          "amount" => "25.00",
          "profile" => {"customerProfileId" => "519123456", "paymentProfile" => {"paymentProfileId" => "527123456"}},
          "order" => {"invoiceNumber" => invoice_number, "description" => reference},
          "transactionSettings" => {"setting" => [{"settingName" => "duplicateWindow", "settingValue" => "28800"}]},
          "processingOptions" => {"isSubsequentAuth" => true}
        )
      end)
    end
  end

  context "when the charge is declined" do
    let(:transaction_fixture) { "create_transaction_declined.json" }

    it "fails the payment with the response reason code" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("authorize_net_error")
      expect(result.error_code).to eq("2")
      expect(payment.reload).to have_attributes(
        provider_payment_id: "80042512346",
        status: "declined",
        payable_payment_status: "failed",
        error_code: "2"
      )
    end
  end

  context "when the charge is held for review" do
    let(:transaction_fixture) { "create_transaction_held_for_review.json" }

    it "keeps the payment processing instead of failing it" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(
        provider_payment_id: "80042512347",
        status: "held_for_review",
        payable_payment_status: "processing"
      )
    end
  end

  context "when Authorize.net reports a duplicate of an earlier attempt" do
    let(:transaction_fixture) { "create_transaction_duplicate.json" }
    let(:listed) { JSON.parse(fixture("unsettled_transaction_list.json")) }

    before do
      stub_const("#{described_class}::LOOKUP_DELAYS_SECONDS", [0, 0, 0, 0])
      stub_request(:post, api_url)
        .with(body: hash_including("getUnsettledTransactionListRequest"))
        .to_return { {status: 200, body: listed.to_json} }
    end

    context "when the earlier attempt shows in the list only on a later lookup" do
      before do
        empty = listed.merge("transactions" => [])
        found = listed.deep_dup.tap { |list| list["transactions"][0]["invoiceNumber"] = invoice_number }

        stub_request(:post, api_url)
          .with(body: hash_including("getUnsettledTransactionListRequest"))
          .to_return({status: 200, body: empty.to_json}, {status: 200, body: found.to_json})
      end

      it "records the earlier transaction" do
        expect(result).to be_success
        expect(result.payment).to have_attributes(provider_payment_id: "80042512399", status: "approved")
        expect(WebMock).to have_requested(:post, api_url).with(body: hash_including("getUnsettledTransactionListRequest")).twice
      end
    end

    context "when the earlier attempt was approved" do
      before { listed["transactions"][0]["invoiceNumber"] = invoice_number }

      it "records the earlier transaction instead of charging again" do
        expect(result).to be_success
        expect(result.payment).to have_attributes(
          provider_payment_id: "80042512399",
          status: "approved",
          payable_payment_status: "succeeded"
        )
      end
    end

    context "when the earlier attempt was declined" do
      before do
        listed["transactions"][0]["invoiceNumber"] = invoice_number
        listed["transactions"][0]["transactionStatus"] = "declined"
      end

      it "fails the payment" do
        expect(result).to be_failure
        expect(payment.reload).to have_attributes(status: "declined", payable_payment_status: "failed", error_code: "11")
      end
    end

    context "when the earlier attempt has a status the provider does not know" do
      before do
        listed["transactions"][0]["invoiceNumber"] = invoice_number
        listed["transactions"][0]["transactionStatus"] = "somethingNew"
      end

      it "keeps the payment processing so nothing charges again" do
        expect(result).to be_success
        expect(result.payment).to have_attributes(
          provider_payment_id: "80042512399",
          status: "held_for_review",
          payable_payment_status: "processing",
          error_code: "11"
        )
      end
    end

    context "when the earlier attempt can't be found" do
      it "keeps the payment processing so nothing charges again" do
        expect(result).to be_success
        expect(WebMock).to have_requested(:post, api_url).with(body: hash_including("getUnsettledTransactionListRequest")).times(4)
        expect(result.payment).to have_attributes(
          provider_payment_id: nil,
          status: "held_for_review",
          payable_payment_status: "processing",
          error_code: "11"
        )
      end
    end
  end

  context "when the customer profile or payment profile is gone" do
    let(:transaction_fixture) { "create_transaction_profile_not_found.json" }

    it "fails the payment with the API error code" do
      expect(result).to be_failure
      expect(result.error_code).to eq("E00040")
      expect(payment.reload).to have_attributes(status: "error", payable_payment_status: "failed", error_code: "E00040")
    end
  end

  context "when the request times out" do
    before do
      stub_request(:post, api_url).with(body: hash_including("createTransactionRequest")).to_timeout
    end

    it "raises a connection error so the job retries with the same invoice number" do
      expect { result }.to raise_error(Invoices::Payments::ConnectionError)
      expect(payment.reload).to have_attributes(status: "pending", payable_payment_status: "pending")
    end
  end

  context "when the payment has no payment method" do
    let(:payment_method) { nil }

    it "fails without calling Authorize.net" do
      expect(result).to be_failure
      expect(result.error_code).to eq("missing_payment_method")
      expect(WebMock).not_to have_requested(:post, api_url)
    end
  end

  context "when the invoice was paid by another payment" do
    before { invoice.update!(payment_status: :succeeded) }

    it "raises without calling Authorize.net" do
      expect { result }.to raise_error(Invoices::Payments::AlreadyPaidError)
      expect(WebMock).not_to have_requested(:post, api_url)
    end
  end
end
