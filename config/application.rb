require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Fall back to the per-deployment SECRET_KEY_BASE persisted by the Docker
# entrypoint when none is provided via ENV. The entrypoint exports it for
# the server process, but `docker compose exec` sessions (migrations,
# console, bin/smoke's token mint) bypass the entrypoint — without this
# they'd fail to boot in production. We only ever read a file the
# operator's own deployment generated; we never ship a key.
if ENV["SECRET_KEY_BASE"].to_s.strip.empty?
  secret_path = ENV.fetch("SECRET_KEY_BASE_PATH", File.expand_path("../storage/secret_key_base", __dir__))
  ENV["SECRET_KEY_BASE"] = File.read(secret_path).strip if File.exist?(secret_path)
end

module Docket
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # English + Hindi at v1.0 (handoff §7); rails-i18n supplies hi base data.
    config.i18n.available_locales = [ :en, :hi ]
    config.i18n.default_locale = :en

    # Admin-allowlisted CORS for /api only (handoff §5).
    require_relative "../lib/docket/cors"
    config.middleware.insert_before 0, Docket::Cors
  end
end
