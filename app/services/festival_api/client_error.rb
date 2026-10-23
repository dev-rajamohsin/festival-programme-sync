module FestivalApi
  # A 4xx response: the request was wrong (bad params, auth, a removed endpoint).
  # Our fault, not transient — retrying won't help.
  class ClientError < Error; end
end
