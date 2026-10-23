module FestivalApi
  # Thin HTTP client for the external festival-management API (mocked at
  # /mock_api/screenings in this app). Knows how to walk the paginated
  # screenings endpoint; it does not touch our database.
  class Client
    DEFAULT_BASE_URL = ENV.fetch("FESTIVAL_API_URL", "http://localhost:3000")

    # The mock delays ~6s with ?slow=true; give upstream generous headroom so a
    # slow-but-alive API reads as success, not a timeout.
    DEFAULT_TIMEOUT = 15

    def initialize(base_url: DEFAULT_BASE_URL, connection: nil)
      @base_url   = base_url
      @connection = connection || build_connection
    end

    # Yields each page's parsed body hash in order, following pagination until the
    # last page. Raises FestivalApi::Error if a page can't be fetched.
    def each_page(generation: 1)
      return enum_for(:each_page, generation: generation) unless block_given?

      page = 1
      loop do
        body = fetch_page(page: page, generation: generation)
        yield body
        total = body.fetch("total_pages", page).to_i
        break if page >= total

        page += 1
      end
    end

    def fetch_page(page:, generation:)
      response = @connection.get("mock_api/screenings", page: page, generation: generation)

      case response.status
      when 200
        response.body
      when 500..599
        raise ServerError, "upstream returned #{response.status} on page #{page}"
      else
        raise ClientError, "upstream returned #{response.status} on page #{page}"
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise ServerError, "upstream unreachable on page #{page}: #{e.message}"
    end

    private

    def build_connection
      Faraday.new(url: @base_url) do |f|
        f.request  :json
        f.response :json
        f.options.timeout      = DEFAULT_TIMEOUT
        f.options.open_timeout = 5
      end
    end
  end
end
