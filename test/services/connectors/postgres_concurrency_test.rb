require "test_helper"

# The production adapter is the only place row-lock concurrency is meaningful.
# This class is intentionally non-transactional so worker threads use separate
# committed connections. SQLite still loads the file and records a harmless
# assertion; the GitHub Postgres leg executes the real races.
class Connectors::PostgresConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @postgres = ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    next unless @postgres

    @tenant = Tenant.find_by!(slug: "primary")
    ActsAsTenant.with_tenant(@tenant) do
      @connector = Connector.create!(
        name: "Concurrency #{SecureRandom.hex(4)}", provider: "http_json", target: "contacts",
        config: { "action_url" => "https://api.example.com/do" },
        field_mapping: { "external_id" => "id" }, enabled_actions: %w[post_json]
      )
      @agent = ServiceAccount.create!(name: "Concurrency agent", scopes: %w[connectors:invoke])
      @agent.grant_connector_actions!(@connector)
      @reviewers = 2.times.map do
        User.create!(name: "Reviewer", email_address: "review-#{SecureRandom.hex(6)}@x.test",
                     password: "password123", role: :client_admin)
      end
    end
  end

  teardown do
    next unless @postgres

    ActsAsTenant.with_tenant(@tenant) do
      ConnectorInvocation.where(connector_id: @connector.id).delete_all
      Connector.with_deleted.where(id: @connector.id).delete_all
      ServiceAccount.with_deleted.where(id: @agent.id).delete_all
      User.with_deleted.where(id: @reviewers.map(&:id)).delete_all
    end
  end

  test "concurrent approval claims execute the provider exactly once" do
    return assert true unless @postgres

    invocation = ActsAsTenant.with_tenant(@tenant) do
      Connectors::Invoke.call(@connector, "post_json", args: { "body" => { "x" => 1 } },
                              principal: @agent)
    end
    calls = 0
    mutex = Mutex.new
    original = Connectors::HttpJsonProvider.instance_method(:invoke)
    Connectors::HttpJsonProvider.define_method(:invoke) do |*_args|
      mutex.synchronize { calls += 1 }
      { "ok" => true }
    end

    errors = race(2) do |index|
      inv = ConnectorInvocation.find(invocation.id)
      Connectors::Invoke.approve!(inv, approver: @reviewers[index])
    end

    assert_empty errors
    assert_equal 1, calls
    assert invocation.reload.status_succeeded?
  ensure
    Connectors::HttpJsonProvider.define_method(:invoke, original) if original
  end

  test "concurrent callers cannot spend the same final principal budget slot" do
    return assert true unless @postgres

    @agent.update!(action_budget: 1, action_budget_window_minutes: 60)
    errors = race(2) do |index|
      Connectors::Invoke.call(@connector, "post_json",
                              args: { "body" => { "request" => index } },
                              principal: @agent)
    end

    assert_equal 1, ConnectorInvocation.where(connector: @connector, requested_by: @agent).count
    assert_equal 1, errors.count { |error| error.is_a?(Connectors::Budget::Exceeded) }
  end

  private

  def race(count)
    ready = Queue.new
    start = Queue.new
    errors = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(@tenant) do
            ready << true
            start.pop
            yield index
          rescue StandardError => e
            errors << e
          end
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    threads.each(&:join)
    errors.size.times.map { errors.pop }
  end
end
