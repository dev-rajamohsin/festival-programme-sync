# Pulls the festival programme (screenings, with their nested films and venues)
# from the external API into our local copy.
#
# Reliability here is idempotency: every record is upserted on its EXTERNAL id,
# never on a human-readable field, so running the sync twice creates no
# duplicates, and a retitled film or renamed venue updates the existing row
# instead of forking a second one.
#
#   ProgrammeSync.call(generation: 1)
class ProgrammeSync
  def self.call(...) = new(...).call

  def initialize(generation: 1, client: FestivalApi::Client.new)
    @generation = generation
    @client     = client
  end

  def call
    @client.each_page(generation: @generation) do |body|
      Array(body["screenings"]).each { |record| import_record(record) }
    end
  end

  private

  def import_record(record)
    film  = upsert_film(record.fetch("film"))
    venue = upsert_venue(record.fetch("venue"))
    upsert_screening(record, film, venue)
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
    screening.assign_attributes(
      film:      film,
      venue:     venue,
      starts_at: record.fetch("starts_at"),
      status:    record.fetch("status")
    )
    screening.save! if screening.changed?
    screening
  end
end
