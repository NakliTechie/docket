require "test_helper"

class ProductionSafetyTest < ActiveSupport::TestCase
  PRODUCTION_CONFIG = Rails.root.join("config/environments/production.rb")
  CI_WORKFLOW = Rails.root.join(".github/workflows/ci.yml")
  DATABASE_CONFIG = Rails.root.join("config/database.yml")
  SMOKE_SCRIPT = Rails.root.join("bin/smoke")
  DOCKERFILE = Rails.root.join("Dockerfile")
  COMPOSE_CONFIG = Rails.root.join("docker-compose.yml")
  RELEASE_SCRIPT = Rails.root.join("bin/release")

  test "both liveness and dependency health endpoints bypass host authorization" do
    body = File.read(PRODUCTION_CONFIG)

    assert_match(%r{%w\[/up /healthz\]\.include\?\(request\.path\)}, body)
  end

  test "release smoke loop is a required CI job" do
    workflow = YAML.safe_load_file(CI_WORKFLOW, aliases: true)
    smoke = workflow.fetch("jobs").fetch("smoke")

    assert_equal "ubuntu-latest", smoke.fetch("runs-on")
    assert smoke.fetch("steps").any? { |step| step["run"] == "bin/smoke" }
  end

  test "CI builds and probes the production image" do
    workflow = YAML.safe_load_file(CI_WORKFLOW, aliases: true)
    package = workflow.fetch("jobs").fetch("package")
    commands = package.fetch("steps").filter_map { |step| step["run"] }.join("\n")

    assert_includes commands, "docker build --tag docket-ci ."
    assert_includes commands, "Rails.version"
    assert_includes commands, "pg_dump"
    assert_includes commands, "pg_restore"
  end

  test "local smoke database tasks run in separate Ruby processes" do
    script = SMOKE_SCRIPT.read

    assert_includes script, "bin/rails db:prepare"
    assert_includes script, "bin/rails db:seed"
    assert_includes script, "bin/rails demo:seed"
    assert_no_match(/bin\/rails db:prepare .*db:seed/, script)
  end

  test "production image precompiles without embedding runtime vault secrets" do
    dockerfile = DOCKERFILE.read
    precompile = dockerfile.lines.grep_v(/^#/).join

    assert_match(/SECRET_KEY_BASE_DUMMY=1.*DOCKET_VAULT_KEYS=.*assets:precompile/m, precompile)
    assert_includes dockerfile, '"active":"build-only"'
    assert_includes dockerfile, "runtime still requires"
  end

  test "production image ships server-matched backup and restore clients" do
    dockerfile = DOCKERFILE.read
    compose = Rails.root.join("docker-compose.yml").read

    assert_includes dockerfile, "postgres:16-bookworm AS postgres-client"
    assert_includes dockerfile, "/usr/lib/postgresql/16/bin/pg_dump"
    assert_includes dockerfile, "/usr/lib/postgresql/16/bin/pg_restore"
    assert_includes compose, "image: postgres:16"
  end

  test "release prepares and base-seeds a newly created production database" do
    release = RELEASE_SCRIPT.read

    assert_includes release, "exec ./bin/rails db:prepare"
    assert_no_match(/db:create db:migrate/, release)
    assert_no_match(/db:seed|demo:seed/, release)
  end

  test "compose forwards documented launch settings without exposing the initial admin password to web" do
    compose = YAML.safe_load_file(COMPOSE_CONFIG, aliases: true)
    common = compose.fetch("x-docket-environment")
    migrate = compose.dig("services", "migrate", "environment")
    app = compose.dig("services", "app", "environment")

    %w[DOCKET_DEPLOYMENT_MODE DOCKET_BASE_DOMAIN DOCKET_VAULT_KEYS
       DOCKET_VAULT_KEYS_PATH RAILS_MAX_THREADS DOCKET_DB_CHECKOUT_TIMEOUT_SECONDS
       DOCKET_DB_CONNECT_TIMEOUT_SECONDS DOCKET_DB_STATEMENT_TIMEOUT DOCKET_DB_LOCK_TIMEOUT
       DOCKET_DB_IDLE_TRANSACTION_TIMEOUT].each do |key|
      assert common.key?(key), "missing #{key}"
    end
    %w[DOCKET_ADMIN_PASSWORD DOCKET_TENANT_NAME].each do |key|
      assert migrate.key?(key), "migrate does not receive #{key}"
    end
    refute app.key?("DOCKET_ADMIN_PASSWORD"), "initial admin password must not remain in web env"

    %w[DOCKET_BASE_URL DOCKET_ALLOWED_HOSTS DOCKET_MAIL_FROM SMTP_ADDRESS SMTP_PASSWORD
       DOCKET_DKIM_DOMAIN DOCKET_DKIM_PRIVATE_KEY_PATH RAILS_INBOUND_EMAIL_PASSWORD
       DOCKET_STAFF_OIDC_ISSUER DOCKET_CUSTOMER_OIDC_ISSUER WEB_CONCURRENCY
       JOB_CONCURRENCY].each do |key|
      assert app.key?(key), "app does not receive #{key}"
    end
  end

  test "compose database pools satisfy the in-process queue supervisor" do
    compose = YAML.safe_load_file(COMPOSE_CONFIG, aliases: true)

    assert_equal "${RAILS_MAX_THREADS:-5}",
                 compose.dig("x-docket-environment", "RAILS_MAX_THREADS")
  end

  test "compose requires an explicit database password" do
    compose = COMPOSE_CONFIG.read

    assert_includes compose, "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD before starting Docket}"
    refute_includes compose, "${POSTGRES_PASSWORD:-docket}"
  end

  test "public base URL drives generated mail links, host authorization, and relay ingress" do
    body = File.read(PRODUCTION_CONFIG)

    assert_includes body, 'ENV["DOCKET_BASE_URL"]'
    assert_includes body, "host: public_base_uri.host"
    assert_includes body, "allowed_hosts << public_base_uri.host"
    assert_includes body,
      'config.action_mailbox.ingress = :relay if ENV["RAILS_INBOUND_EMAIL_PASSWORD"].present?'
  end

  test "production databases have bounded waits and query execution" do
    rendered = ERB.new(File.read(DATABASE_CONFIG)).result
    production = YAML.safe_load(rendered, aliases: true).fetch("production").fetch("primary")

    assert_equal "30s", production.dig("variables", "statement_timeout")
    assert_equal "5s", production.dig("variables", "lock_timeout")
    assert_equal 5, production.fetch("connect_timeout")
    assert_equal 5, production.fetch("checkout_timeout")
  end

  test "sibling database URLs preserve query parameters" do
    old = ENV["DATABASE_URL"]
    ENV["DATABASE_URL"] = "postgres://db.example/docket?sslmode=require&application_name=docket"
    rendered = ERB.new(File.read(DATABASE_CONFIG)).result
    production = YAML.safe_load(rendered, aliases: true).fetch("production")

    assert_equal "postgres://db.example/docket_cache?sslmode=require&application_name=docket",
                 production.dig("cache", "url")
    assert_equal "postgres://db.example/docket_queue?sslmode=require&application_name=docket",
                 production.dig("queue", "url")
    assert_equal "postgres://db.example/docket_cable?sslmode=require&application_name=docket",
                 production.dig("cable", "url")
  ensure
    ENV["DATABASE_URL"] = old
  end

  test "request and abuse timeouts use process-shared production state" do
    request_timeout = Rails.root.join("config/initializers/request_timeout.rb").read
    rack_attack = Rails.root.join("config/initializers/rack_attack.rb").read

    assert_match(/service_timeout.*RACK_TIMEOUT_SERVICE_TIMEOUT/m, request_timeout)
    assert_includes rack_attack, "Rack::Attack.cache.store = Rails.cache"
    assert_includes rack_attack, 'Rack::Attack.throttle("health/check"'
  end
end
