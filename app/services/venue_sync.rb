# Keeps our local venue records in step with the upstream festival system.
#
# Inherited from the previous programming integration. Given an array of venue
# hashes from the API, it upserts each one into our venues table.
#
#   VenueSync.new(venues_payload).call
#
# where each entry looks like:
#   { "id" => "VEN-01", "name" => "Grand Cinema", "address" => "...", "capacity" => 320 }
#
# NOTE: this originally matched on `name`, which meant an upstream rename created
# a *second* venue row instead of updating the first — the classic "matched on a
# human-readable field" integration bug. It now upserts on the external id, which
# is stable across renames.
class VenueSync
  def initialize(venues)
    @venues = venues
  end

  def call
    @venues.each do |attrs|
      venue = Venue.find_or_initialize_by(external_id: attrs.fetch("id"))
      venue.name     = attrs.fetch("name")
      venue.address  = attrs["address"]
      venue.capacity = attrs["capacity"]
      venue.save!
    end
  end
end
