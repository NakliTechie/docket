class CaseMerge
  def self.call(...) = new(...).call

  def initialize(source:, target:, actor:)
    @source = source
    @target = target
    @actor = actor
  end

  def call
    validate!
    Case.transaction do
      [ @source, @target ].sort_by(&:id).each(&:lock!)
      validate!
      move_messages
      move_work_links
      move_import_identities
      @source.case_presences.delete_all
      Imports::Mode.run do
        @source.update!(merged_into: @target, merged_at: Time.current,
                        status: :closed, closed_at: Time.current)
        @target.messages.create!(kind: :internal_note, direction: :outbound, author: @actor,
                                 body: I18n.t("case_merge.note", source: @source.tracking_id))
      end
    end
    @target
  end

  private

  def validate!
    raise ArgumentError, "a case cannot merge into itself" if @source.id == @target.id
    raise ArgumentError, "cases must belong to the same tenant" if @source.tenant_id != @target.tenant_id
    raise ArgumentError, "cases must have the same contact" if @source.contact_id != @target.contact_id
    raise ArgumentError, "source case is already merged" if @source.merged_into_id?
    raise ArgumentError, "target case is already merged" if @target.merged_into_id?
  end

  def move_messages
    @source.messages.with_deleted.find_each { |message| message.update!(case: @target) }
  end

  def move_work_links
    @source.work_links.find_each do |link|
      duplicate = WorkLink.find_by(work_item: link.work_item, linkable: @target)
      duplicate ? link.destroy! : link.update!(linkable: @target)
    end
  end

  def move_import_identities
    ImportIdentity.where(target: @source).find_each { |identity| identity.update!(target: @target) }
  end
end
