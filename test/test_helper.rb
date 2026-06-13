ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/api_test_helper"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Default every test to the primary tenant so scoped reads/writes work the
    # way an isolated deploy does. Cross-tenant tests override with
    # ActsAsTenant.with_tenant(...) or by resolving a subdomain per request.
    setup { ActsAsTenant.test_tenant = tenants(:primary) }
    teardown { ActsAsTenant.test_tenant = nil }

    # Add more helper methods to be used by all tests here...
  end
end
