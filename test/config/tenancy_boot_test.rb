require "test_helper"

# H28: the tenancy initializer validates DOCKET_DEPLOYMENT_MODE at boot, so a
# typo can't silently serve the wrong topology (isolated? = !shared?, so any
# unrecognised value falls through to isolated).
class TenancyBootTest < ActiveSupport::TestCase
  # This test process booted with the default mode — proof a valid mode works.
  test "a valid deployment mode boots" do
    assert_includes Tenant::DEPLOYMENT_MODES, Tenant.deployment_mode
  end

  # An invalid mode must fail boot loudly rather than fall through. Boot a child
  # process with a typo'd value and confirm it never comes up.
  test "an invalid deployment mode fails boot" do
    out = IO.popen({ "DOCKET_DEPLOYMENT_MODE" => "Shared" },
                   [ "bin/rails", "runner", "puts 'BOOTED'" ],
                   err: [ :child, :out ], chdir: Rails.root.to_s, &:read)
    refute $?.success?, "a typo'd mode must abort boot"
    refute_match(/BOOTED/, out, "the app must not come up")
    assert_match(/DOCKET_DEPLOYMENT_MODE must be one of/, out)
  end
end
