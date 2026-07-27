# Operator-facing health, deeper than Rails' /up (which only proves the process
# booted). Unauthenticated so a load balancer or an uptime check can read it,
# and deliberately shallow in what it reveals: check names and up/down, never
# hostnames, versions, counts of business records or error messages beyond an
# exception class.
class HealthController < ActionController::API
  def show
    result = HealthCheck.call
    render json: result.to_h, status: result.ok ? :ok : :service_unavailable
  end
end
