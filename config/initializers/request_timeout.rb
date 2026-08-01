# Abort a web request before it can occupy one of Puma's limited threads
# indefinitely. Long imports and maintenance run as jobs/tasks, outside Rack.
unless Rails.env.test?
  Rails.application.config.middleware.insert_before(
    Rack::Runtime,
    Rack::Timeout,
    service_timeout: ENV.fetch("RACK_TIMEOUT_SERVICE_TIMEOUT", 25).to_i
  )
end
