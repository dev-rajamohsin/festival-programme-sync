# Pulls the festival programme (screenings, with their nested films and venues)
# from the external API into our local copy.
#
# Design goals, in priority order:
#
#   * Idempotent. Every record is upserted on its EXTERNAL id, never on a
#     human-readable field, so running twice creates no duplicates and a retitled
#     film or renamed venue updates the existing row instead of forking it.
#
#   * Correct under partial failure. Each record is imported in its own
#     transaction, so a single bad record is isolated and reported without
#     abandoning the batch, and whatever already succeeded stays committed. If the
#     upstream API itself dies partway, the pages we already imported are kept and
#     the run is marked failed so the job can retry.
#
#   * Observable. Every run is recorded in a SyncRun: status, timing, created /
#     updated / failed counts, and the captured per-record errors.
#
#   ProgrammeSync.call(generation: 1)   #=> #<SyncRun status: "succeeded", ...>
class ProgrammeSync
  def self.call(...) = new(...).call

  def initialize(generation: 1, client: FestivalApi::Client.new)
    @generation = generation
    @client     = client
  end


  def call
    run = SyncRun.create!(status: :running, generation: @generation, started_at: Time.current)

    begin
      @client.each_page(generation: @generation) do |body|
        Array(body["screenings"]).each { |record| import_record(record, run) }
      end
      run.status = :succeeded
    rescue FestivalApi::Error => e

      run.status        = :failed
      run.error_message = e.message
      raise
    ensure
      run.finished_at = Time.current
      run.save!
    end

    run
  end

  private

  def import_record(record, run)
    ApplicationRecord.transaction(requires_new: true) do
      film  = upsert_film(record.fetch("film"))
      venue = upsert_venue(record.fetch("venue"))
      created = upsert_screening(record, film, venue)
      created ? run.created_count += 1 : run.updated_count += 1
    end
  rescue StandardError => e

    run.failed_count += 1
    run.record_errors << { "external_id" => record["id"], "error" => e.message }
    Rails.logger.warn("[ProgrammeSync] skipped record #{record['id'].inspect}: #{e.message}")
  end

  def upsert_film(attrs)
    film = Film.find_or_initialize_by(external_id: attrs.fetch("id"))
    film.assign_attributes(
      title:    attrs.fetch("title"),
      synopsis: attrs["synopsis"],
      runtime:  attrs["runtime"],
      year:     attrs["year"]
    )
    film.save! if film.changed?
    film
  end

  def upsert_venue(attrs)
    venue = Venue.find_or_initialize_by(external_id: attrs.fetch("id"))
    venue.assign_attributes(
      name:     attrs.fetch("name"),
      address:  attrs["address"],
      capacity: attrs["capacity"]
    )
    venue.save! if venue.changed?
    venue
  end

  def upsert_screening(record, film, venue)
    screening = Screening.find_or_initialize_by(external_id: record.fetch("id"))
    created   = screening.new_record?
    screening.assign_attributes(
      film:      film,
      venue:     venue,
      starts_at: record.fetch("starts_at"),
      status:    record.fetch("status")
    )
    screening.save! if screening.changed?
    created
  end
end
