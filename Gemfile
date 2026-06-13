source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record (dev/test/demo); Postgres in production
gem "sqlite3", ">= 2.1"
gem "pg", "~> 1.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Authorization policies (single authorisation layer, used everywhere)
gem "pundit", "~> 2.3"

# Tenant scoping for shared multi-tenant deploys. Pure Ruby (no runtime deps
# beyond request_store), fail-closed on a missing tenant. Isolated deploys are
# the degenerate single-tenant case. See plan/rbac-research-2026-06-13.md.
gem "acts_as_tenant", "~> 1.0"

# Public portal rate limiting
gem "rack-attack", "~> 6.7"

# Pagination — dependency-free
gem "pagy", "~> 9.4"

# Locale data (Hindi base translations for AR errors, dates, numbers)
gem "rails-i18n", "~> 8.0"

# Stdlib gem from Ruby 3.4 (activity CSV export)
gem "csv"

# PDF text extraction for AI grounding reference docs (pure ruby)
gem "pdf-reader", "~> 2.12"

# Dual SSO (handoff §5A): staff OIDC + SAML, customer OIDC
gem "omniauth", "~> 2.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"
gem "omniauth_openid_connect", "~> 0.8"
gem "omniauth-saml", "~> 2.2"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  # CDP driver — no chromedriver binary needed, just a Chrome/Chromium
  gem "cuprite"
  # HTTP stubbing for webhook delivery tests
  gem "webmock"
end
