# A faithful in-memory stand-in for the external festival API, used to drive the
# programme sync in tests without a network or a running server.
#
# It serves MockApi::Dataset through a Faraday test adapter using the SAME
# pagination and fail_after semantics as MockApi::ScreeningsController, so the
# sync is exercised against the real contract it depends on.
#
#   client = MockFestivalApi.client                 # healthy upstream
#   client = MockFestivalApi.client(fail_after: 8)  # 8 records, then 500s
module MockFestivalApi
  module_function

  # Returns a FestivalApi::Client wired to the stub. `fail_after` reproduces the
  # ?fail_after=N failure mode (N records escape across pages, then a 500).
  def client(fail_after: nil)
    connection = Faraday.new do |f|
      f.response :json
      f.adapter :test do |stub|
        stub.get("/mock_api/screenings") { |env| respond(env, fail_after) }
      end
    end

    FestivalApi::Client.new(connection: connection)
  end

  def respond(env, fail_after)
    params     = Rack::Utils.parse_nested_query(env.url.query)
    generation = params.fetch("generation", 1)
    page       = [ params.fetch("page", 1).to_i, 1 ].max
    per_page   = MockApi::Dataset::PER_PAGE
    offset     = (page - 1) * per_page

    all = MockApi::Dataset.records(generation: generation)

    if fail_after && offset >= fail_after
      return json(500, error: "Upstream festival system unavailable")
    end

    slice = all[offset, per_page] || []
    slice = slice.first([ fail_after - offset, 0 ].max) if fail_after

    json(200,
      page:        page,
      per_page:    per_page,
      total_pages: (all.size.to_f / per_page).ceil,
      total_count: all.size,
      screenings:  slice)
  end

  def json(status, payload)
    [ status, { "Content-Type" => "application/json" }, payload.to_json ]
  end
end
