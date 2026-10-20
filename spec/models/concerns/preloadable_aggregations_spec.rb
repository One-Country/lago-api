# frozen_string_literal: true

require "rails_helper"

# Exercised through Invoice and Fee, which declare both an own aggregation
# (offset/refunded amounts) and an associated one (fees' credited amount).
RSpec.describe PreloadableAggregations do
  let(:invoice) { create(:invoice) }

  def count_queries
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless /\A\s*(SAVEPOINT|RELEASE|BEGIN|COMMIT|ROLLBACK)/i.match?(payload[:sql])
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  before do
    create(:credit_note, invoice:, offset_amount_cents: 5_00, refund_amount_cents: 5_00)
    create(:credit_note, invoice:, offset_amount_cents: 10_00, refund_amount_cents: 10_00)
    create(:credit_note, invoice:, offset_amount_cents: 20_00, refund_amount_cents: 20_00, status: :draft)

    credit_note = create(:credit_note, invoice:)
    fee1 = create(:fee, invoice:)
    fee2 = create(:fee, invoice:)

    create(:credit_note_item, credit_note:, fee: fee1, amount_cents: 5_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 10_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 15_00)
  end

  describe ".preload_aggregations" do
    context "when no names are passed" do
      it "caches every own and associated aggregation" do
        Invoice.preload_aggregations([invoice])

        expect(invoice.aggregation_cache).to eq(
          offset_amount_cents: 15_00,
          refunded_amount_cents: 35_00
        )
        expect(invoice.fees.first.aggregation_cache).to eq(credited_amount_cents: 5_00)
        expect(invoice.fees.last.aggregation_cache).to eq(credited_amount_cents: 25_00)
      end

      it "reads the cached values without extra queries" do
        Invoice.preload_aggregations([invoice])

        queries = count_queries do
          expect(invoice.offset_amount_cents).to eq(15_00)
          expect(invoice.refunded_amount_cents).to eq(35_00)
          expect(invoice.fees.map(&:credited_amount_cents)).to eq([5_00, 25_00])
        end

        expect(queries).to eq(0)
      end
    end

    context "when specific names are passed" do
      it "caches only the named own aggregation" do
        Invoice.preload_aggregations([invoice], :offset_amount_cents)

        expect(invoice.aggregation_cache).to eq(offset_amount_cents: 15_00)
        expect(invoice.fees.map(&:aggregation_cache)).to all(eq({}))
      end
    end

    context "when the records are empty" do
      it "does not run any query" do
        expect(count_queries { Invoice.preload_aggregations([]) }).to eq(0)
      end
    end
  end

  describe "generated reader" do
    context "when the value was not preloaded" do
      it "falls back to a single-record query and caches it" do
        expect(invoice.offset_amount_cents).to eq(15_00)
        expect(invoice.aggregation_cache[:offset_amount_cents]).to eq(15_00)
      end
    end

    context "when the preloaded value is zero" do
      it "returns the cached zero without falling back" do
        invoice.aggregation_cache[:offset_amount_cents] = 0

        queries = count_queries { expect(invoice.offset_amount_cents).to eq(0) }

        expect(queries).to eq(0)
      end
    end
  end
end
