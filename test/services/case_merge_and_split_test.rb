require "test_helper"

class CaseMergeAndSplitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "merge moves the complete case history and leaves a canonical lineage" do
    target = cases(:pension_case)
    source = Case.create!(subject: "Duplicate pension case", contact: target.contact,
                          channel: :staff)
    message = source.messages.create!(body: "Customer supplied passbook proof", direction: :inbound,
                                      author: target.contact)
    link = WorkLink.create!(work_item: work_items(:pep_one), linkable: source,
                            created_by: users(:admin))
    identity = ImportIdentity.create!(source: "freshdesk", source_instance: "pilot",
                                      source_type: "ticket", external_id: "FD-merge-1",
                                      target: source)

    result = CaseMerge.call(source: source, target: target, actor: users(:admin))

    assert_equal target, result
    assert_equal target, source.reload.merged_into
    assert source.status_closed?
    assert_equal target, source.canonical_record
    assert_equal target, message.reload.case
    assert_equal target, link.reload.linkable
    assert_equal target, identity.reload.target
    assert target.messages.kind_internal_note.exists?(body: I18n.t("case_merge.note", source: source.tracking_id))
  end

  test "merge rejects a different contact without changing either case" do
    source = cases(:pension_case)
    target = cases(:assigned_case)

    assert_raises(ArgumentError) do
      CaseMerge.call(source: source, target: target, actor: users(:admin))
    end

    assert_nil source.reload.merged_into
    assert_equal "new", source.status
  end

  test "split moves only selected messages with their attachments and emits no outbound jobs" do
    source = cases(:pension_case)
    selected = source.messages.create!(body: "Move this", kind: :public_reply, direction: :outbound,
                                       author: users(:admin))
    selected.files.attach(io: StringIO.new("proof"), filename: "proof.txt", content_type: "text/plain")
    stays = source.messages.create!(body: "Keep this", kind: :internal_note, author: users(:admin))
    clear_enqueued_jobs

    created = nil
    assert_no_enqueued_jobs do
      created = CaseSplit.call(source: source, message_ids: [ selected.id ],
                               subject: "Separate request", actor: users(:admin))
    end

    assert_equal created, selected.reload.case
    assert_equal [ "proof.txt" ], selected.files.map { |file| file.filename.to_s }
    assert_equal source, stays.reload.case
    assert_equal source.contact, created.contact
    assert_equal source.queue, created.queue
    assert source.messages.kind_internal_note.exists?(body: I18n.t("case_split.source_note", target: created.tracking_id))
    assert created.messages.kind_internal_note.exists?(body: I18n.t("case_split.target_note", source: source.tracking_id))
  end
end
