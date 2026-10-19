# frozen_string_literal: true

module Clock
  class X402SignInNoncesCleanupJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 10_000
    RETENTION_PERIOD = 1.day

    def perform
      X402::SignInNonce.where(created_at: ...RETENTION_PERIOD.ago)
        .in_batches(of: BATCH_SIZE, use_ranges: true)
        .delete_all
    end
  end
end
