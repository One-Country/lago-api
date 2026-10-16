# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::FeesController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee_attributes) do
    {
      invoice:,
      subscription: nil,
      fee_type: :product,
      invoiceable: contract_rate_card.rate_card.product,
      contract:,
      contract_rate_card:
    }
  end
  let(:uninvoiced_fee_attributes) do
    fee_attributes.merge(invoice: nil, organization:, billing_entity: customer.billing_entity)
  end
  let(:fee) { create(:fee, fee_attributes) }
  let(:legacy_fee) { create(:fee, invoice:) }
  let(:fee_id) { fee.id }

  describe "GET /api/v2/fees" do
    subject { get_with_token(organization, "/api/v2/fees", params) }

    let(:params) { {} }

    before do
      fee
      legacy_fee
    end

    include_examples "requires API permission", "fee", "read"

    it "lists the product fees only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fees].sole).to include(lago_id: fee.id, external_contract_id: contract.external_id, billing_timing: "arrears")
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :fees, model: Fee do
      let(:paginated_path) { "/api/v2/fees" }
      let(:create_paginated_record) { ->(created_at) { create(:fee, fee_attributes.merge(created_at:)) } }
    end

    context "with filters" do
      let(:params) { {payment_status: "succeeded", external_customer_id: customer.external_id} }
      let(:succeeded_fee) { create(:fee, :succeeded, uninvoiced_fee_attributes) }
      let(:other_contract_rate_card) { create(:contract_rate_card, organization:) }

      before do
        succeeded_fee
        create(
          :fee,
          :succeeded,
          fee_attributes.merge(
            invoice: create(:invoice, organization:, customer: other_contract_rate_card.contract.customer),
            contract: other_contract_rate_card.contract,
            contract_rate_card: other_contract_rate_card
          )
        )
      end

      it "passes them to the query" do
        subject

        expect(json[:fees].map { it[:lago_id] }).to eq([succeeded_fee.id])
      end
    end

    context "with an unknown payment status" do
      let(:params) { {payment_status: "paid"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :payment_status)).to eq(["value_is_invalid"])
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v2/fees/:id" do
    subject { get_with_token(organization, "/api/v2/fees/#{fee_id}") }

    include_examples "requires API permission", "fee", "read"

    it "returns the fee" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fee]).to include(lago_id: fee.id, lago_invoice_id: invoice.id, billing_timing: "arrears")
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("fee")
      end
    end

    context "when the fee belongs to another organization" do
      let(:fee_id) { create(:fee, fee_attributes.merge(invoice: create(:invoice), contract: nil, contract_rate_card: nil)).id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("fee")
      end
    end
  end

  describe "PUT /api/v2/fees/:id" do
    subject { put_with_token(organization, "/api/v2/fees/#{fee_id}", fee: {payment_status:}) }

    let(:fee) { create(:fee, uninvoiced_fee_attributes) }
    let(:payment_status) { "succeeded" }

    include_examples "requires API permission", "fee", "write"

    it "updates the payment status and returns the fee" do
      freeze_time do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:fee]).to include(lago_id: fee.id, payment_status: "succeeded", succeeded_at: Time.current.iso8601, billing_timing: "arrears")
        expect(fee.reload).to be_payment_succeeded
      end
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("fee")
        expect(legacy_fee.reload).to be_payment_pending
      end
    end

    context "when the fee is invoiced" do
      let(:fee) { create(:fee, fee_attributes) }

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("invoiced_fee")
        expect(fee.reload).to be_payment_pending
      end
    end

    context "with an unknown payment status" do
      let(:payment_status) { "paid" }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :payment_status)).to eq(["value_is_invalid"])
      end
    end
  end

  describe "DELETE /api/v2/fees/:id" do
    subject { delete_with_token(organization, "/api/v2/fees/#{fee_id}") }

    let(:fee) { create(:fee, uninvoiced_fee_attributes) }

    include_examples "requires API permission", "fee", "write"

    it "discards the fee and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fee]).to include(lago_id: fee.id, billing_timing: "arrears")
      expect(Fee.with_discarded.find(fee.id)).to be_discarded
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("fee")
        expect(legacy_fee.reload).to be_kept
      end
    end

    context "when the fee is invoiced" do
      let(:fee) { create(:fee, fee_attributes) }

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("invoiced_fee")
        expect(fee.reload).to be_kept
      end
    end
  end
end
