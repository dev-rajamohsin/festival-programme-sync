class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      # running | succeeded | failed. "failed" means the upstream API died
      # partway; a run can also succeed while reporting per-record failures.
      t.string   :status,        null: false, default: "running"
      t.integer  :generation
      t.datetime :started_at,    null: false
      t.datetime :finished_at

      t.integer  :created_count, null: false, default: 0
      t.integer  :updated_count, null: false, default: 0
      t.integer  :failed_count,  null: false, default: 0

      t.string   :error_message
      t.jsonb    :record_errors, null: false, default: []

      t.timestamps
    end

    add_index :sync_runs, :status
    add_index :sync_runs, :started_at
  end
end
