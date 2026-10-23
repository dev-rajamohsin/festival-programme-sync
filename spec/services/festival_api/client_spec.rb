require "rails_helper"

RSpec.describe FestivalApi::Client do
  describe "#each_page" do
    it "walks every page in order until the last one" do
      pages = MockFestivalApi.client.each_page(generation: 1).to_a

      expect(pages.size).to eq(3) # 60 records / 25 per page
      expect(pages.map { |p| p["page"] }).to eq([ 1, 2, 3 ])
      expect(pages.sum { |p| p["screenings"].size }).to eq(60)
    end

    it "raises a ServerError when the upstream fails partway" do
      expect do
        MockFestivalApi.client(fail_after: 8).each_page(generation: 1).to_a
      end.to raise_error(FestivalApi::ServerError, /500/)
    end
  end

  describe "#fetch_page error mapping" do
    def client_returning(status)
      connection = Faraday.new do |f|
        f.response :json
        f.adapter :test do |stub|
          stub.get("/mock_api/screenings") { [ status, { "Content-Type" => "application/json" }, "{}" ] }
        end
      end
      described_class.new(connection: connection)
    end

    it "maps 5xx to a (retryable) ServerError" do
      expect { client_returning(503).fetch_page(page: 1, generation: 1) }
        .to raise_error(FestivalApi::ServerError)
    end

    it "maps 4xx to a (non-retryable) ClientError" do
      expect { client_returning(404).fetch_page(page: 1, generation: 1) }
        .to raise_error(FestivalApi::ClientError)
    end
  end
end
