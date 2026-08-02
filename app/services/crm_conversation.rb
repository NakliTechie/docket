class CrmConversation
  LIMIT = 100
  Entry = Data.define(:record, :context, :channel, :direction, :author, :subject_line, :body, :occurred_at)

  def self.call(subject, limit: LIMIT, case_scope: Case.none, contact_scope: Contact.none,
                lead_scope: Lead.none, deal_scope: Deal.none,
                visible_types: [ subject.class.name ])
    new(subject, limit: limit, case_scope: case_scope, contact_scope: contact_scope,
         lead_scope: lead_scope, deal_scope: deal_scope, visible_types: visible_types).call
  end

  def self.recipient_email(subject)
    case subject
    when Contact, Lead then subject.email
    when Deal then subject.contact&.email || subject.lead&.email
    end
  end

  def initialize(subject, limit:, case_scope:, contact_scope:, lead_scope:, deal_scope:, visible_types:)
    @subject = subject
    @limit = limit
    @case_scope = case_scope
    @contact_scope = contact_scope
    @lead_scope = lead_scope
    @deal_scope = deal_scope
    @visible_types = visible_types
  end

  def call
    (crm_entries + case_entries).sort_by(&:occurred_at).reverse.first(@limit)
  end

  private

  def crm_entries
    subject_query.preload(:author).recent_first.limit(@limit).map do |message|
      Entry.new(
        record: message,
        context: context_for(message.subject),
        channel: message.channel,
        direction: message.direction,
        author: message.display_author,
        subject_line: message.subject_line,
        body: message.body,
        occurred_at: message.occurred_at
      )
    end
  end

  def case_entries
    contact_ids = linked_contact_ids
    return [] if contact_ids.empty?

    messages = Message.joins(:case).preload(:author, :case)
                      .where(case_id: @case_scope.select(:id))
                      .where(cases: { contact_id: contact_ids })
                      .where(kind: %w[public_reply agent_turn])
                      .order(created_at: :desc).limit(@limit)
    messages.map do |message|
      Entry.new(
        record: message,
        context: message.case.tracking_id,
        channel: message.case.channel,
        direction: message.direction,
        author: message.author_display_name,
        subject_line: message.subject.presence || message.case.subject,
        body: message.body,
        occurred_at: message.created_at
      )
    end
  end

  def subject_query
    pairs = linked_subjects.group_by { |record| record.class.name }
    pairs.reduce(CrmMessage.none) do |relation, (type, records)|
      relation.or(CrmMessage.where(subject_type: type, subject_id: records.map(&:id)))
    end
  end

  def linked_subjects
    records = [ @subject ]
    case @subject
    when Contact
      records.concat(@lead_scope.where(contact: @subject).to_a) if visible?("Lead")
      records.concat(@deal_scope.where(contact: @subject).to_a) if visible?("Deal")
    when Lead
      records << @contact_scope.find_by(id: @subject.contact_id) if visible?("Contact")
      records << @deal_scope.find_by(id: @subject.converted_deal_id) if visible?("Deal")
    when Deal
      records << @contact_scope.find_by(id: @subject.contact_id) if visible?("Contact")
      records << @lead_scope.find_by(id: @subject.lead_id) if visible?("Lead")
    end
    records.compact.uniq
  end

  def visible?(type) = @visible_types.include?(type)

  def linked_contact_ids
    linked_subjects.filter_map do |record|
      case record
      when Contact then record.id
      when Lead then record.contact_id
      when Deal then record.contact_id
      end
    end.uniq
  end

  def context_for(subject)
    case subject
    when Contact then subject.name
    when Lead then I18n.t("crm_messages.context.lead", name: subject.name)
    when Deal then I18n.t("crm_messages.context.deal", name: subject.name)
    end
  end
end
