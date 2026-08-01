class Customer360
  LIMIT = 20
  # The unified stream is capped, and so is each source before the merge, so a
  # contact with thousands of messages can't unbounded-load the workspace.
  TIMELINE_LIMIT = 40
  # Communications only — the AI's internal agent_turn reasoning stays on the
  # case, out of the customer's interaction history.
  TIMELINE_MESSAGE_KINDS = %w[public_reply internal_note].freeze

  Result = Data.define(:cases, :case_count, :deals, :deal_count, :work_items, :work_item_count, :timeline)

  # One entry in the unified chronological stream. +record+ is the underlying
  # Case / Message / Deal / WorkItem so the view can link straight to it; +kind+
  # names the event so the view picks its icon/label without re-deriving it.
  Event = Data.define(:at, :kind, :record, :title)

  def initialize(subject:, case_scope: Case.none, deal_scope: Deal.none, work_scope: WorkItem.none,
                 activity_scope: Activity.none)
    @subject = subject
    @case_scope = case_scope
    @deal_scope = deal_scope
    @work_scope = work_scope
    @activity_scope = activity_scope
  end

  def call
    cases = case_relation
    deals = deal_relation
    work_items = work_relation(deals)
    activities = activity_relation(cases, deals)
    Result.new(
      cases: cases.order(created_at: :desc).limit(LIMIT).to_a, case_count: cases.count,
      deals: deals.order(updated_at: :desc).limit(LIMIT).to_a, deal_count: deals.count,
      work_items: work_items.order(updated_at: :desc).limit(LIMIT).to_a,
      work_item_count: work_items.count,
      timeline: timeline(cases, deals, work_items, activities)
    )
  end

  private

  # The "single view": cases, communications and resolutions across the subject,
  # interleaved newest-first. An off/absent module contributes a `.none` scope,
  # so its events simply don't appear — the timeline inherits the same
  # entitlement gating as the summary panels.
  def timeline(cases, deals, work_items, activities)
    events = case_events(cases) + message_events(cases) + deal_events(deals) +
             work_events(work_items) + activity_events(activities)
    events.select(&:at).sort_by(&:at).reverse.first(TIMELINE_LIMIT)
  end

  # Activities directly on the subject (a Contact), plus those on its deals and
  # cases, interleaved into the stream. An off CRM module passes Activity.none.
  def activity_relation(cases, deals)
    @activity_scope.where(subject: @subject)
                   .or(@activity_scope.where(subject_type: "Deal", subject_id: deals.select(:id)))
                   .or(@activity_scope.where(subject_type: "Case", subject_id: cases.select(:id)))
  end

  def activity_events(activities)
    activities.order(created_at: :desc).limit(TIMELINE_LIMIT).map do |activity|
      Event.new(at: activity.created_at, kind: :activity, record: activity, title: activity.title)
    end
  end

  def case_events(cases)
    cases.order(created_at: :desc).limit(TIMELINE_LIMIT).flat_map do |kase|
      events = [ Event.new(at: kase.created_at, kind: :case_opened, record: kase, title: kase.subject) ]
      events << Event.new(at: kase.resolved_at, kind: :case_resolved, record: kase, title: kase.subject) if kase.resolved_at
      events << Event.new(at: kase.closed_at, kind: :case_closed, record: kase, title: kase.subject) if kase.closed_at
      events
    end
  end

  def message_events(cases)
    Message.includes(:case)
           .where(case_id: cases.select(:id), kind: TIMELINE_MESSAGE_KINDS)
           .order(created_at: :desc).limit(TIMELINE_LIMIT)
           .map { |message| Event.new(at: message.created_at, kind: :message, record: message, title: message.case.subject) }
  end

  def deal_events(deals)
    deals.order(updated_at: :desc).limit(TIMELINE_LIMIT).flat_map do |deal|
      events = [ Event.new(at: deal.created_at, kind: :deal_opened, record: deal, title: deal.name) ]
      if deal.closed_at && deal.status != "open"
        kind = deal.status == "won" ? :deal_won : :deal_lost
        events << Event.new(at: deal.closed_at, kind: kind, record: deal, title: deal.name)
      end
      events
    end
  end

  def work_events(work_items)
    # includes(:project) — the link helper reads item.reference (project.key),
    # so preload it the same way message_events preloads the case.
    work_items.includes(:project).order(updated_at: :desc).limit(TIMELINE_LIMIT).flat_map do |item|
      events = [ Event.new(at: item.created_at, kind: :work_opened, record: item, title: item.title) ]
      events << Event.new(at: item.closed_at, kind: :work_closed, record: item, title: item.title) if item.closed_at
      events
    end
  end

  def case_relation
    relation = @case_scope.canonical
    @subject.is_a?(Contact) ? relation.where(contact: @subject) : relation.joins(:contact).where(contacts: { organisation_id: @subject.id })
  end

  def deal_relation
    if @subject.is_a?(Contact)
      @deal_scope.where(contact: @subject)
    else
      @deal_scope.where(organisation: @subject)
    end
  end

  def work_relation(deals)
    contact_ids = @subject.is_a?(Contact) ? [ @subject.id ] : @subject.contacts.ids
    predicates = WorkLink.where(linkable_type: "Contact", linkable_id: contact_ids)
    predicates = predicates.or(WorkLink.where(linkable_type: "Deal", linkable_id: deals.select(:id)))
    @work_scope.where(id: predicates.select(:work_item_id))
  end
end
