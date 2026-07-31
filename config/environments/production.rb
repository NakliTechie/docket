require "active_support/core_ext/integer/time"
require "uri"

# DOCKET_BASE_URL is the canonical public origin. Reuse it for generated mail
# links and Host authorization so a documented Compose deployment cannot serve
# successfully while emailing localhost:3000 URLs or rejecting its own public
# hostname. Existing deployments that only set DOCKET_HOST/DOCKET_PORT keep the
# compatibility fallback below.
public_base_uri = if ENV["DOCKET_BASE_URL"].present?
  uri = URI.parse(ENV.fetch("DOCKET_BASE_URL"))
  origin_only = (uri.path.blank? || uri.path == "/") && uri.query.nil? && uri.fragment.nil?
  unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && origin_only
    raise ArgumentError, "DOCKET_BASE_URL must be an http(s) origin without userinfo, path, query, or fragment"
  end
  uri
end

Rails.application.configure do
  # The generic relay ingress accepts complete RFC 822 messages from the
  # operator-owned mail pipeline. Rails protects it with
  # RAILS_INBOUND_EMAIL_PASSWORD; Compose forwards that variable explicitly.
  config.action_mailbox.ingress = :relay if ENV["RAILS_INBOUND_EMAIL_PASSWORD"].present?

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Attachment links (rails_blob_path) carry a signed blob id that, left
  # unset, never expires — a leaked portal attachment URL would work forever
  # with no auth. Expire them so a customer's document link is short-lived;
  # re-opening the (auth-gated) tracking/my-cases page mints a fresh one.
  config.active_storage.urls_expire_in = 1.hour

  # SSL is on by default (sovereign posture). The compose quickstart
  # serves plain HTTP on localhost, so it sets DOCKET_FORCE_SSL=false.
  config.assume_ssl = ENV["DOCKET_FORCE_SSL"] != "false"
  config.force_ssl = ENV["DOCKET_FORCE_SSL"] != "false"

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Outbound mail goes only through the operator-configured SMTP
  # gateway; with no SMTP configured, mail is silently discarded —
  # never any other egress (handoff §8).
  if ENV["SMTP_ADDRESS"].present?
    config.x.outbound_mail_available = true
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV["SMTP_USERNAME"].present? ? :login : nil,
      enable_starttls_auto: ENV["SMTP_STARTTLS"] != "false"
    }.compact
  else
    config.x.outbound_mail_available = false
    config.action_mailer.delivery_method = :docket_null
  end

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = if public_base_uri
    {
      host: public_base_uri.host,
      protocol: public_base_uri.scheme,
      port: (public_base_uri.port unless public_base_uri.port == public_base_uri.default_port)
    }.compact
  else
    {
      host: ENV.fetch("DOCKET_HOST", "localhost"),
      port: ENV["DOCKET_PORT"].presence
    }.compact
  end

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS-rebinding / Host-header protection follows the canonical base URL.
  # DOCKET_ALLOWED_HOSTS adds proxy/IP aliases and DOCKET_HOST remains a
  # compatibility input. Only a legacy deployment with all three unset keeps
  # Rails' unrestricted default. /up and operator-grade /healthz stay reachable
  # for health checks regardless.
  allowed_hosts = ENV["DOCKET_ALLOWED_HOSTS"].to_s.split(",").map(&:strip).reject(&:blank?)
  allowed_hosts << ENV["DOCKET_HOST"] if ENV["DOCKET_HOST"].present?
  allowed_hosts << public_base_uri.host if public_base_uri
  # Shared deployments serve every tenant on a subdomain of the base domain, so
  # allow the whole `*.base-domain` space (a leading dot matches the domain and
  # all its subdomains). Isolated deployments stay pinned to their single host.
  if ENV["DOCKET_DEPLOYMENT_MODE"] == "shared" && ENV["DOCKET_BASE_DOMAIN"].present?
    allowed_hosts << ".#{ENV['DOCKET_BASE_DOMAIN']}"
  end
  config.hosts.concat(allowed_hosts.uniq) if allowed_hosts.any?
  config.host_authorization = { exclude: ->(request) { %w[/up /healthz].include?(request.path) } }
end
