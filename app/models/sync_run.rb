# A record of one programme sync run, so we can tell afterwards whether a sync
# succeeded and what it did. Written by ProgrammeSync.
#
#   SyncRun.recent.first.summary
#   #=> "succeeded: 2 created, 58 updated, 0 failed in 1.2s"
class SyncRun < ApplicationRecord
  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, default: "running"

  scope :recent, -> { order(started_at: :desc) }

  # Succeeded overall but some individual records could not be imported. Worth
  # alerting on even though the run "finished".
  def completed_with_errors?
    succeeded? && failed_count.positive?
  end

  def duration
    return unless finished_at
    finished_at - started_at
  end

  def summary
    parts = [ "#{created_count} created", "#{updated_count} updated", "#{failed_count} failed" ]
    parts << format("%.1fs", duration) if duration
    "#{status}: #{parts.join(', ')}"
  end
end
