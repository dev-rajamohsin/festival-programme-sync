require "rails_helper"

RSpec.describe ProgrammeSync do
  # Generation 1 is 60 screenings across 12 films and 6 venues.
  GEN1_SCREENINGS = 60
  FILMS_COUNT     = 12
  VENUES_COUNT    = 6

  def sync(generation: 1, fail_after: nil)
    described_class.call(generation: generation, client: MockFestivalApi.client(fail_after: fail_after))
  end

  describe "a clean first run (generation 1)" do
    it "imports every screening with its film and venue" do
      run = sync(generation: 1)

      expect(Screening.count).to eq(GEN1_SCREENINGS)
      expect(Film.count).to eq(FILMS_COUNT)
      expect(Venue.count).to eq(VENUES_COUNT)

      expect(run).to be_succeeded
      expect(run.created_count).to eq(GEN1_SCREENINGS)
      expect(run.updated_count).to eq(0)
      expect(run.failed_count).to eq(0)
      expect(run.finished_at).to be_present
    end
  end

  describe "idempotency" do
    it "creates no duplicates when run twice" do
      sync(generation: 1)

      expect { sync(generation: 1) }.not_to change { [ Screening.count, Film.count, Venue.count ] }
    end

    it "reports the second run as all updates, no creates" do
      sync(generation: 1)
      run = sync(generation: 1)

      expect(run.created_count).to eq(0)
      expect(run.updated_count).to eq(GEN1_SCREENINGS)
    end
  end

  describe "applying upstream changes (generation 1 then generation 2)" do
    before { sync(generation: 1) }

    it "updates the retitled film in place, keeping one record on the same id" do
      sync(generation: 2)

      films = Film.where(external_id: "FILM-005")
      expect(films.count).to eq(1)
      expect(films.first.title).to eq("Autumn in Trieste (Director's Cut)")
      expect(Film.count).to eq(FILMS_COUNT) # no duplicate forked off the rename
    end

    it "updates the renamed venue in place, keeping one record on the same id" do
      sync(generation: 2)

      venues = Venue.where(external_id: "VEN-03")
      expect(venues.count).to eq(1)
      expect(venues.first.name).to eq("City Gallery Auditorium")
      expect(Venue.count).to eq(VENUES_COUNT)
    end

    it "moves screenings to their new venue" do
      sync(generation: 2)

      expect(Screening.find_by(external_id: "SCR-0001").venue.external_id).to eq("VEN-06")
      expect(Screening.find_by(external_id: "SCR-0004").venue.external_id).to eq("VEN-05")
    end

    it "propagates cancellations" do
      sync(generation: 2)

      %w[SCR-0010 SCR-0011 SCR-0012].each do |id|
        expect(Screening.find_by(external_id: id)).to be_cancelled
      end
    end

    it "inserts the newly added screenings" do
      sync(generation: 2)

      expect(Screening.find_by(external_id: "SCR-0061")).to be_present
      expect(Screening.find_by(external_id: "SCR-0062")).to be_present
    end

    # We intentionally do NOT prune screenings dropped upstream (see README): a
    # full sync can't safely tell "deleted" from "didn't appear in this fetch".
    it "leaves a screening removed upstream in place (deletions are not pruned)" do
      sync(generation: 2)

      expect(Screening.find_by(external_id: "SCR-0060")).to be_present
    end
  end

  describe "partial failure: the API dies mid-run" do
    it "keeps the records already retrieved and marks the run failed" do
      expect { sync(generation: 1, fail_after: 8) }.to raise_error(FestivalApi::ServerError)

      # The 8 records that escaped before the 500 are committed, not rolled back.
      expect(Screening.count).to eq(8)

      run = SyncRun.recent.first
      expect(run).to be_failed
      expect(run.error_message).to match(/500/)
      expect(run.created_count).to eq(8)
      expect(run.record_errors).to be_empty # an API failure is not a record failure
    end

    it "recovers on a later healthy run, losing nothing" do
      expect { sync(generation: 1, fail_after: 8) }.to raise_error(FestivalApi::ServerError)
      expect(Screening.count).to eq(8)

      run = sync(generation: 1)

      expect(Screening.count).to eq(GEN1_SCREENINGS)
      expect(run).to be_succeeded
      expect(run.created_count).to eq(GEN1_SCREENINGS - 8) # the 52 missing ones
      expect(run.updated_count).to eq(8)                   # the 8 already present
    end
  end

  describe "partial failure: a single bad record" do
    # A page with one good record and one missing its film title. The bad record
    # must be isolated and reported, not abort the batch, and it's a DATA error,
    # distinct from a dead API.
    def client_with_one_bad_record
      good = MockApi::Dataset.generation_one.first
      bad  = Marshal.load(Marshal.dump(good)).merge("id" => "SCR-9999")
      bad["film"].delete("title")

      body = { page: 1, per_page: 25, total_pages: 1, total_count: 2, screenings: [ good, bad ] }

      connection = Faraday.new do |f|
        f.response :json
        f.adapter :test do |stub|
          stub.get("/mock_api/screenings") { [ 200, { "Content-Type" => "application/json" }, body.to_json ] }
        end
      end
      FestivalApi::Client.new(connection: connection)
    end

    it "commits the good record, captures the bad one, and still succeeds" do
      run = described_class.call(generation: 1, client: client_with_one_bad_record)

      expect(run).to be_succeeded
      expect(run.created_count).to eq(1)
      expect(run.failed_count).to eq(1)
      expect(run.record_errors.first["external_id"]).to eq("SCR-9999")
      expect(Screening.find_by(external_id: "SCR-9999")).to be_nil
      expect(run.completed_with_errors?).to be(true)
    end
  end
end
