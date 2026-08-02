# Independent row-level scope for human users. Permissions still answer what a
# persona may do; this class narrows which operational records that permission
# reaches. Every relation remains inside ActsAsTenant's active tenant.
class RecordVisibility
  SUPPORTED_MODELS = %w[
    Case Contact Organisation Lead Deal WorkItem Project Activity Decision
  ].freeze

  def self.resolve(user, scope, access: :read)
    new(user, scope, access: access).resolve
  end

  def self.allowed?(user, record, access: :read)
    return false unless user
    return true if record.is_a?(Class) || record.new_record?
    return true if user.record_scope_for(access) == "global"

    base = if record.respond_to?(:deleted?) && record.deleted? && record.class.respond_to?(:with_deleted)
      record.class.with_deleted
    else
      record.class.all
    end
    resolve(user, base.where(record.class.primary_key => record.id), access: access).exists?
  end

  def initialize(user, scope, access:)
    @user = user
    @base = scope.all
    @model = @base.klass
    @access = access.to_sym
  end

  def resolve
    return @base.none unless @user
    return @base if scope_name == "global"
    return @base.none unless SUPPORTED_MODELS.include?(@model.name)

    send("#{@model.model_name.element}_scope")
  end

  private

  def scope_name
    @scope_name ||= @user.record_scope_for(@access)
  end

  def owned_or_assigned_ids(ids = [ @user.id ])
    case @model.name
    when "Case" then union(@base.where(owner_id: ids), @base.where(assignee_id: ids))
    when "Contact", "Organisation", "Lead", "Deal", "Activity"
      @base.where(owner_id: ids)
    when "WorkItem" then union(@base.where(reporter_id: ids), @base.where(assignee_id: ids))
    when "Project" then @base.where(lead_id: ids)
    else @base.none
    end
  end

  def owned_ids(ids = [ @user.id ])
    case @model.name
    when "Case", "Contact", "Organisation", "Lead", "Deal", "Activity"
      @base.where(owner_id: ids)
    when "WorkItem" then @base.where(reporter_id: ids)
    when "Project" then @base.where(lead_id: ids)
    else @base.none
    end
  end

  def case_scope
    return owned_ids if scope_name == "owned"
    return owned_or_assigned_ids if scope_name == "assigned"
    return owned_or_assigned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      @base.where(queue_id: queue_ids)
    elsif scope_name == "account"
      @base.where(contact_id: Contact.where(organisation_id: account_ids).select(:id))
    end
    union(owned_or_assigned_ids, related)
  end

  def contact_scope
    return owned_ids if %w[owned assigned].include?(scope_name)
    return owned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      @base.where(id: Case.where(queue_id: queue_ids).select(:contact_id))
    elsif scope_name == "account"
      @base.where(organisation_id: account_ids)
    end
    union(owned_ids, related)
  end

  def organisation_scope
    return owned_ids if %w[owned assigned].include?(scope_name)
    return owned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      contact_ids = Case.where(queue_id: queue_ids).select(:contact_id)
      @base.where(id: Contact.where(id: contact_ids).select(:organisation_id))
    elsif scope_name == "account"
      @base.where(id: account_ids)
    end
    union(owned_ids, related)
  end

  def lead_scope
    return owned_ids if %w[owned assigned].include?(scope_name)
    return owned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      @base.where(contact_id: contact_ids_for_queues)
    elsif scope_name == "account"
      @base.where(contact_id: Contact.where(organisation_id: account_ids).select(:id))
    end
    union(owned_ids, related)
  end

  def deal_scope
    return owned_ids if %w[owned assigned].include?(scope_name)
    return owned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      contacts = Contact.where(id: contact_ids_for_queues)
      union(@base.where(contact_id: contacts.select(:id)),
            @base.where(organisation_id: contacts.select(:organisation_id)))
    elsif scope_name == "account"
      union(@base.where(organisation_id: account_ids),
            @base.where(contact_id: Contact.where(organisation_id: account_ids).select(:id)))
    end
    union(owned_ids, related)
  end

  def work_item_scope
    return owned_ids if scope_name == "owned"
    return owned_or_assigned_ids if scope_name == "assigned"
    return owned_or_assigned_ids(team_user_ids) if scope_name == "team"

    related = if scope_name == "queue"
      linked_work_items("Case", Case.where(queue_id: queue_ids).select(:id))
    elsif scope_name == "account"
      account_work_items
    end
    union(owned_or_assigned_ids, related)
  end

  def project_scope
    direct = scope_name == "team" ? owned_ids(team_user_ids) : owned_ids
    return direct if @access == :write

    items = RecordVisibility.resolve(@user, WorkItem.all, access: @access)
    union(direct, @base.where(id: items.select(:project_id)))
  end

  def activity_scope
    return owned_ids if %w[owned assigned].include?(scope_name)
    return owned_ids(team_user_ids) if scope_name == "team"

    related = %w[Case Contact Organisation Lead Deal WorkItem].map do |type|
      model = type.constantize
      visible = RecordVisibility.resolve(@user, model.all, access: @access)
      @base.where(subject_type: type, subject_id: visible.select(:id))
    end
    union(owned_ids, *related)
  end

  def decision_scope
    related = %w[Case Contact Organisation Lead Deal WorkItem Project Activity].map do |type|
      model = type.constantize
      base = model.respond_to?(:with_deleted) ? model.with_deleted : model.all
      visible = RecordVisibility.resolve(@user, base, access: @access)
      @base.where(subject_type: type, subject_id: visible.select(:id))
    end
    union(*related)
  end

  def queue_ids
    @queue_ids ||= @user.queue_memberships.pluck(:queue_id)
  end

  def team_user_ids
    @team_user_ids ||= begin
      team_ids = @user.team_memberships.select(:team_id)
      (TeamMembership.where(team_id: team_ids).pluck(:user_id) + [ @user.id ]).uniq
    end
  end

  def account_ids
    @account_ids ||= begin
      roots = @user.scoped_accounts.includes(:children).to_a
      roots.flat_map(&:self_and_descendants).map(&:id).uniq
    end
  end

  def contact_ids_for_queues
    Case.where(queue_id: queue_ids).select(:contact_id)
  end

  def linked_work_items(type, ids)
    @base.where(id: WorkLink.where(linkable_type: type, linkable_id: ids).select(:work_item_id))
  end

  def account_work_items
    contacts = Contact.where(organisation_id: account_ids)
    cases = Case.where(contact_id: contacts.select(:id))
    deals = Deal.where(organisation_id: account_ids)
                .or(Deal.where(contact_id: contacts.select(:id)))
    links = [
      linked_work_items("Organisation", account_ids),
      linked_work_items("Contact", contacts.select(:id)),
      linked_work_items("Case", cases.select(:id)),
      linked_work_items("Deal", deals.select(:id))
    ]
    onboarding = @base.where(project_id: Project.where(onboarding_deal_id: deals.select(:id)).select(:id))
    union(*links, onboarding)
  end

  def union(*relations)
    relations.compact.reduce(@base.none) { |combined, relation| combined.or(relation) }
  end
end
