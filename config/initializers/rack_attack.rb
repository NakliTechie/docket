# Public portal abuse protection (handoff §8). Backed by Rails.cache
# (Solid Cache) — no Redis.
Rack::Attack.enabled = !Rails.env.test?
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

Rack::Attack.throttle("portal/submissions", limit: 20, period: 1.hour) do |request|
  request.ip if request.post? && request.path.start_with?("/portal/cases")
end

Rack::Attack.throttle("portal/tracking", limit: 15, period: 15.minutes) do |request|
  request.ip if request.post? && request.path.start_with?("/portal/track")
end

Rack::Attack.throttle("portal/general", limit: 300, period: 5.minutes) do |request|
  request.ip if request.path.start_with?("/portal")
end

# OAuth client-credentials endpoint: each exchange runs bcrypt, so an
# unthrottled endpoint is both a brute-force vector on client secrets and
# a CPU-DoS. Legit integrations refresh ~hourly (1h token TTL), so this is
# generous for real use (M25).
Rack::Attack.throttle("api/oauth_token", limit: 30, period: 5.minutes) do |request|
  request.ip if request.post? && request.path == "/api/v1/oauth/token"
end

Rack::Attack.throttled_responder = lambda do |_request|
  [ 429, { "Content-Type" => "text/plain" }, [ "Rate limit exceeded. Please retry later.\n" ] ]
end
