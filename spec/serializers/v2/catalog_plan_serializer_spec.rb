# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CatalogPlanSerializer do
  subject(:serializer) { described_class.new(catalog_plan, root_name: "plan", includes:) }

  let(:catalog_plan) { create(:catalog_plan) }
  let(:includes) { [] }
  let(:result) { JSON.parse(serializer.to_json) }
  let(:flat_payload) do
    {
      "lago_id" => catalog_plan.id,
      "name" => catalog_plan.name,
      "invoice_display_name" => catalog_plan.invoice_display_name,
      "code" => catalog_plan.code,
      "description" => catalog_plan.description,
      "currency" => catalog_plan.currency,
      "created_at" => catalog_plan.created_at.iso8601,
      "deleted_at" => nil
    }
  end

  # Two kept rate cards on the plan, next to cards that no count may include.
  before do
    create_list(:plan_rate_card, 2, organization: catalog_plan.organization, catalog_plan:)
    create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:, deleted_at: Time.current)
    create(:plan_rate_card, organization: catalog_plan.organization)
  end

  it "serializes the catalog plan, without counts" do
    expect(result["plan"]).to eq(flat_payload)
  end

  context "when counts are included" do
    let(:includes) { %i[counts] }

    it "counts the kept rate cards of the plan" do
      expect(result["plan"]).to eq(flat_payload.merge("applied_rate_cards_count" => 2))
    end
  end

  context "when taxes are included" do
    let(:includes) { %i[taxes] }
    let(:tax) { create(:tax, organization: catalog_plan.organization) }

    before { create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization: catalog_plan.organization) }

    it "serializes the catalog plan taxes" do
      expect(result["plan"]["taxes"]).to contain_exactly(include("lago_id" => tax.id, "code" => tax.code))
    end
  end
end
