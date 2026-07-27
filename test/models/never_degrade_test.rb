require "test_helper"

# The launch contract's never-degrade list, asserted rather than assumed.
class NeverDegradeTest < ActiveSupport::TestCase
  test "an untouched (dedicated-deploy) tenant has every feature on" do
    t = tenants(:primary)
    assert_empty t.entitlements, "a fresh tenant stores no overrides"
    off = Features::KEYS.reject { |k| t.feature?(k) }
    assert_empty off, "isolated deploys must behave exactly as before entitlements existed"
  end

  test "every new work model is tenant-scoped, soft-deletable where it should be, and audited" do
    %w[Project WorkItem WorkComment Sprint WorkLink WorkflowState
       ProjectMembership WorkWatch].each do |name|
      klass = name.constantize
      assert_includes klass.column_names, "tenant_id", "#{name} must be tenant-scoped"
    end

    %w[Project WorkItem WorkComment Sprint WorkLink].each do |name|
      assert name.constantize.include?(Audited), "#{name} must be in the audit chain"
    end

    %w[Project WorkItem WorkComment Sprint WorkflowState].each do |name|
      assert name.constantize.include?(SoftDeletable), "#{name} must soft-delete"
    end
  end

  test "cross-tenant reads of work data are empty" do
    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert_empty WorkItem.where(id: work_items(:pep_one).id)
      assert_empty Project.where(id: projects(:pep).id)
    end
  end
end
