# Provider callbacks: no session, no CSRF token (providers can't send one) — each subclass
# authenticates the request itself before touching any data.
class Webhooks::BaseController < ActionController::API
  rate_limit to: 600, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }
end
