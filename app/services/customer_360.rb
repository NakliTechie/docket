class Customer360
  LIMIT = 20

  Result = Data.define(:cases, :case_count, :deals, :deal_count, :work_items, :work_item_count)

  def initialize(subject:, case_scope: Case.none, deal_scope: Deal.none, work_scope: WorkItem.none)
    @subject = subject
    @case_scope = case_scope
    @deal_scope = deal_scope
    @work_scope = work_scope
  end

  def call
    cases = case_relation
    deals = deal_relation
    work_items = work_relation(deals)
    Result.new(
      cases: cases.order(created_at: :desc).limit(LIMIT).to_a, case_count: cases.count,
      deals: deals.order(updated_at: :desc).limit(LIMIT).to_a, deal_count: deals.count,
      work_items: work_items.order(updated_at: :desc).limit(LIMIT).to_a,
      work_item_count: work_items.count
    )
  end

  private

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
