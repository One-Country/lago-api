# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::PaymentRequestsController do
  describe "GET /api/v2/customers/:external_id/payment_requests" do
    subject { get_with_token(organization, "/api/v2/customers/#{external_id}/payment_requests", params) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:external_id) { customer.external_id }
    let(:params) { {} }
    let(:contract_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:legacy_invoice) { create(:invoice, organization:, customer:) }
    let(:payment_request) { create(:payment_request, customer:, invoices: [contract_invoice, legacy_invoice]) }

    before do
      payment_request
      create(:payment_request, customer: create(:customer, organization:))
    end

    include_examples "requires API permission", "payment_request", "read"

    it "lists the payment requests of the customer only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].map { it[:lago_id] }).to eq([payment_request.id])
      expect(json[:meta]).to include(current_page: 1, total_count: 1)
    end

    it "renders catalog invoices with the v2 shape and legacy invoices with the v1 shape" do
      subject

      invoices = json[:payment_requests].sole[:invoices].index_by { it[:lago_id] }

      expect(invoices.keys).to contain_exactly(contract_invoice.id, legacy_invoice.id)
      expect(invoices[contract_invoice.id]).to include(invoice_type: "contract")
      expect(invoices[contract_invoice.id]).not_to have_key(:sequential_id)
      expect(invoices[legacy_invoice.id]).to include(sequential_id: legacy_invoice.sequential_id)
    end

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end
  end
end
