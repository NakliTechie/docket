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
    # way an isolated deploy does. Use the normal ambient slot, not
    # ActsAsTenant.test_tenant: that hard pin silently beat `with_tenant` and
    # made our second-tenant tests continue querying primary.
    setup do
      ActsAsTenant.current_tenant = tenants(:primary)
      I18n.locale = I18n.default_locale
    end
    teardown do
      ActsAsTenant.current_tenant = nil
      Current.reset
      I18n.locale = I18n.default_locale
    end

    # Add more helper methods to be used by all tests here...
  end
end
