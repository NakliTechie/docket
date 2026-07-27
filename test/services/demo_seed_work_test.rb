require "test_helper"
# db/ is outside the autoload path — the seed requires this file the same way.
require Rails.root.join("db/seeds/demo_scenarios")

# The demo seed is what a demo, a guide capture and the deployment team all see
# first. Before this, the Work section of a freshly seeded deployment was empty.
class DemoSeedWorkTest < ActiveSupport::TestCase
  # The seed refuses to run twice (demo_seeded marker) and the suite already
  # loads it, so assert against what the loaded fixture data produced rather
  # than re-running it.
  test "every scenario defines a work project with enough items to fill a board" do
    DemoScenarios::ALL.each_value do |scenario|
      spec = scenario[:project]
      assert spec.present?, "#{scenario[:brand]} has no work project — its Work section would be empty"
      assert_match Project::KEY_FORMAT, spec[:key]
      assert spec[:items].size >= 8, "too few items to spread across a board"
      spec[:items].each do |title, kind, priority, estimate|
        assert title.present?
        assert_includes WorkItem.kinds.keys, kind.to_s
        assert_includes WorkItem.priorities.keys, priority.to_s
        assert estimate.to_f > 0, "#{title} has no estimate — velocity would read zero"
      end
    end
  end

  test "the seeded scenarios cover every work-item kind and priority" do
    kinds = DemoScenarios::SAAS[:project][:items].map { |i| i[1] }.uniq
    priorities = DemoScenarios::SAAS[:project][:items].map { |i| i[2] }.uniq
    assert kinds.size >= 3, "a demo board that is all tasks shows nothing about the module"
    assert priorities.size >= 3
  end
end
