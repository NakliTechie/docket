require "test_helper"

# The base seed (db/seeds.rb) must give a fresh, non-demo deploy a usable
# ticketing floor on day one — a default queue + a default SLA policy, wired
# as the Settings-driven defaults — without clobbering an operator who has
# already configured things, and idempotent across re-runs.
class BaseSeedTest < ActiveSupport::TestCase
  def load_seeds
    capture_io { load Rails.root.join("db/seeds.rb").to_s }
  end

  # Simulate a truly empty install: drop the ticketing tables (nulling the
  # nullable case refs and removing the null:false children first) and clear
  # the default-pointer settings.
  def empty_the_ticketing_tables
    Case.unscoped.update_all(queue_id: nil, sla_policy_id: nil)
    QueueMembership.delete_all
    CaseQueue.unscoped.delete_all
    SlaTarget.delete_all
    SlaPolicy.unscoped.delete_all
    Setting.unset("default_queue_id")
    Setting.unset("default_sla_policy_id")
  end

  test "a fresh install gets a default queue and SLA wired as the defaults" do
    empty_the_ticketing_tables
    categories_before = Category.count

    load_seeds

    queue = CaseQueue.find_by!(name: "General")
    assert_equal queue, CaseQueue.default, "default_queue_id should point at the seeded queue"

    sla = SlaPolicy.find_by!(name: "Standard")
    assert_equal %w[high low normal urgent], sla.sla_targets.map(&:priority).sort
    assert_equal sla, SlaPolicy.default, "default_sla_policy_id should point at the seeded SLA"

    assert_equal categories_before, Category.count, "the floor must not invent categories (opt-in)"
  end

  test "re-running the seed is a no-op (no duplicates)" do
    empty_the_ticketing_tables
    load_seeds
    load_seeds

    assert_equal 1, CaseQueue.where(name: "General").count
    assert_equal 1, SlaPolicy.where(name: "Standard").count
    assert_equal 4, SlaPolicy.find_by!(name: "Standard").sla_targets.count
  end

  test "an operator's existing setup is left untouched" do
    empty_the_ticketing_tables
    CaseQueue.create!(name: "Operator Queue")
    SlaPolicy.create!(name: "Operator SLA")

    load_seeds

    assert_not CaseQueue.exists?(name: "General"), "must not seed a queue when one already exists"
    assert_not SlaPolicy.exists?(name: "Standard"), "must not seed an SLA when one already exists"
  end
end
