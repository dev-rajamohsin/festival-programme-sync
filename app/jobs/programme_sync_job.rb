# Runs the programme sync in the background, on a schedule (see config/schedule.yml)
# and on demand.
#
# The job is safe to run repeatedly: ProgrammeSync upserts on external id, so a
# duplicate or overlapping enqueue never corrupts the local copy. Two guards back
# that up:
#
#   * retry_on only for transient upstream failures. A 5xx / timeout is worth
#     retrying with backoff; a bad individual record is captured by ProgrammeSync
#     and must not trigger a retry of the whole run.
#
#   * a Postgres advisory lock, so if a run is still in flight (slow upstream)
#     when the next one is enqueued, the newcomer skips rather than running a
#     redundant, competing sync.
class ProgrammeSyncJob < ApplicationJob
  queue_as :default

  # Transient upstream failure: back off and retry. ClientError (4xx) and
  # per-record data errors are deliberately NOT retried.
  retry_on FestivalApi::ServerError, wait: :polynomially_longer, attempts: 5

  # Stable key for pg_try_advisory_lock. Must be deterministic across worker
  # processes, so crc32 (not String#hash, which is per-process seeded).
  ADVISORY_LOCK_ID = Zlib.crc32("programme_sync")

  def perform(generation: 1)
    unless acquire_lock
      Rails.logger.info("[ProgrammeSyncJob] a sync is already running; skipping this run")
      return
    end

    begin
      run = ProgrammeSync.call(generation: generation)
      Rails.logger.info("[ProgrammeSyncJob] #{run.summary}")
    ensure
      release_lock
    end
  end

  private

  def acquire_lock
    ApplicationRecord.connection.select_value(
      "SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_ID})"
    )
  end

  def release_lock
    ApplicationRecord.connection.select_value(
      "SELECT pg_advisory_unlock(#{ADVISORY_LOCK_ID})"
    )
  end
end
