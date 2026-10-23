module FestivalApi
  # A 5xx response or timeout: the upstream is (temporarily) unhealthy. Transient,
  # so it's worth retrying with backoff.
  class ServerError < Error; end
end
