require "rails_helper"

RSpec.describe VenueSync do
  describe "#call" do
    it "creates a venue that doesn't exist yet" do
      payload = [
        { "id" => "VEN-01", "name" => "Grand Cinema", "address" => "12 Main Street", "capacity" => 320 }
      ]

      expect { VenueSync.new(payload).call }.to change(Venue, :count).by(1)

      venue = Venue.find_by(external_id: "VEN-01")
      expect(venue).to have_attributes(
        name: "Grand Cinema",
        address: "12 Main Street",
        capacity: 320
      )
    end

    # The bug the original service shipped with: a rename upstream (same id, new
    # name) must UPDATE the existing venue, not create a duplicate.
    it "updates the existing venue when it is renamed upstream" do
      VenueSync.new([ { "id" => "VEN-03", "name" => "City Gallery Screening Room", "capacity" => 90 } ]).call

      expect do
        VenueSync.new([ { "id" => "VEN-03", "name" => "City Gallery Auditorium", "capacity" => 90 } ]).call
      end.not_to change(Venue, :count)

      expect(Venue.where(external_id: "VEN-03").pluck(:name)).to eq([ "City Gallery Auditorium" ])
    end

    it "is idempotent across repeated runs" do
      payload = [ { "id" => "VEN-01", "name" => "Grand Cinema", "capacity" => 320 } ]

      VenueSync.new(payload).call
      expect { VenueSync.new(payload).call }.not_to change(Venue, :count)
    end

    it "isolates a bad record and reports it without abandoning the batch" do
      payload = [
        { "id" => "VEN-01", "name" => "Grand Cinema", "capacity" => 320 },
        { "id" => "VEN-02", "name" => "", "capacity" => 180 } # invalid: name required
      ]

      failures = VenueSync.new(payload).call

      expect(Venue.find_by(external_id: "VEN-01")).to be_present
      expect(failures.size).to eq(1)
      expect(failures.first[:attrs]["id"]).to eq("VEN-02")
    end
  end
end
