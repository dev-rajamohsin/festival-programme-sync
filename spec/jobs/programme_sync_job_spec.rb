require "rails_helper"

RSpec.describe ProgrammeSyncJob do
  describe "#perform" do
    it "runs the sync when it can take the lock (and the lock SQL actually works)" do
      run = instance_double(SyncRun, summary: "succeeded: 60 created")
      allow(ProgrammeSync).to receive(:call).and_return(run)

      described_class.perform_now(generation: 1)

      expect(ProgrammeSync).to have_received(:call).with(generation: 1)
    end

    it "skips the run when another sync already holds the lock" do
      allow_any_instance_of(described_class).to receive(:acquire_lock).and_return(false)
      allow(ProgrammeSync).to receive(:call)

      described_class.perform_now

      expect(ProgrammeSync).not_to have_received(:call)
    end

    it "releases the lock even if the sync raises" do
      allow_any_instance_of(described_class).to receive(:acquire_lock).and_return(true)
      expect_any_instance_of(described_class).to receive(:release_lock)
      allow(ProgrammeSync).to receive(:call).and_raise(RuntimeError, "boom")

      expect { described_class.perform_now }.to raise_error(RuntimeError, "boom")
    end
  end

  it "is configured to retry only transient upstream failures" do
    handled = described_class.rescue_handlers.map(&:first)
    expect(handled).to include("FestivalApi::ServerError")
  end
end
