require "test_helper"

# Cross-tenant referential integrity for the Work module.
#
# acts_as_tenant scopes READS, so a foreign record is invisible — but an
# OPTIONAL belongs_to skips the existence check entirely, so mass-assigning a
# guessed id from another tenant was stored happily. The row then points at
# something nobody in this tenant can see: the association reads nil, and any
# future unscoped query (a report, a notification, an export) reads across the
# boundary.
class WorkTenantIntegrityTest < ActiveSupport::TestCase
  def acme_user
    ActsAsTenant.with_tenant(tenants(:acme)) do
      User.create!(name: "Acme Person", email_address: "person@acme.test",
                   password: "password", role: :customer_service)
    end
  end

  test "a work item cannot be assigned to another tenant's user" do
    item = work_items(:pep_one)
    refute item.update(assignee_id: acme_user.id),
           "a foreign assignee is invisible here — storing it silently breaks the row"
    assert item.errors.of_kind?(:assignee, :cross_tenant)
  end

  test "a work item cannot report to another tenant's user" do
    item = work_items(:pep_one)
    refute item.update(reporter_id: acme_user.id)
  end

  test "a project's lead must belong to the project's tenant" do
    project = projects(:pep)
    refute project.update(lead_id: acme_user.id)
    assert project.errors.of_kind?(:lead, :cross_tenant)
  end

  test "a work link cannot point at another tenant's record" do
    foreign_case = ActsAsTenant.with_tenant(tenants(:acme)) do
      Case.create!(subject: "Acme private matter", description: "secret",
                   contact: Contact.create!(name: "A", email: "a@acme.test"))
    end

    link = WorkLink.new(work_item: work_items(:pep_one), linkable: foreign_case)
    refute link.valid?, "linking across tenants leaks the linked record's content"
    assert link.errors.of_kind?(:linkable, :cross_tenant)
  end

  test "escalation refuses a case and project from different tenants" do
    foreign_project = ActsAsTenant.with_tenant(tenants(:acme)) do
      Project.create!(key: "ACM2", name: "Acme work")
    end

    assert_raises(ArgumentError) do
      Work::Escalation.call(kase: cases(:pension_case), project: foreign_project,
                            actor: users(:admin))
    end
  end

  test "same-tenant references still work (the guard is not blanket-denying)" do
    item = work_items(:pep_one)
    assert item.update(assignee_id: users(:agent_a).id)
    assert projects(:pep).update(lead_id: users(:admin).id)
    assert WorkLink.new(work_item: item, linkable: cases(:pension_case)).valid?
  end

  # Every custom validation on this module rendered as raw "Translation
  # missing…" text — in a flash message and in the API's error body. A user
  # would have seen the i18n lookup path instead of a sentence.
  test "every custom work-module validation has a real message in both locales" do
    cases = [
      [ WorkItem.new(project: projects(:pep), title: "x"), :parent, :cycle ],
      [ WorkItem.new(project: projects(:pep), title: "x"), :workflow_state, :not_in_project ],
      [ WorkItem.new(project: projects(:pep), title: "x"), :sprint, :not_in_project ],
      [ Sprint.new(project: projects(:pep), name: "x"), :status, :another_sprint_active ],
      [ Sprint.new(project: projects(:pep), name: "x"), :ends_on, :before_start ],
      [ Project.new(key: "X", name: "x"), :lead, :cross_tenant ],
      [ WorkLink.new(work_item: work_items(:pep_one)), :linkable, :cross_tenant ]
    ]

    %i[en hi].each do |locale|
      I18n.with_locale(locale) do
        cases.each do |record, attribute, kind|
          record.errors.clear
          record.errors.add(attribute, kind)
          message = record.errors.full_messages.first
          refute_match(/translation missing/i, message,
                       "#{record.class}##{attribute}:#{kind} has no #{locale} message")
          assert message.present?
        end
      end
    end
  end
end
