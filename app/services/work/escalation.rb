module Work
  # "This case needs engineering." Opens a work item in the chosen project and
  # links it back to the case, so the desk keeps ownership of the customer
  # conversation while the work is tracked where engineers actually work.
  #
  # The case is NOT transitioned — the agent decides whether to keep it open,
  # move it to waiting, or resolve it. Escalating is not a status change.
  class Escalation
    Result = Struct.new(:work_item, :link, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(kase:, project:, actor:, title: nil, description: nil, kind: :bug, priority: nil)
      @case = kase
      @project = project
      @actor = actor
      @title = title.presence || kase.subject
      @description = description
      @kind = kind
      @priority = priority
    end

    def call
      item = nil
      link = nil

      ActiveRecord::Base.transaction do
        item = @project.work_items.create!(
          title: @title,
          description: @description.presence || default_description,
          kind: @kind,
          # Desk and work share one priority vocabulary, so urgency survives
          # the hand-off instead of being re-guessed.
          priority: @priority.presence || @case.priority,
          reporter: @actor
        )
        link = WorkLink.create!(work_item: item, linkable: @case,
                                relation: :escalated_from, created_by: @actor)
        note_on_case(item)
      end

      Result.new(work_item: item, link: link)
    end

    private

    def default_description
      [ I18n.t("work.escalation.from_case", tracking_id: @case.tracking_id),
        @case.description ].compact.join("\n\n")
    end

    # An internal note, never a customer-visible reply — the customer did not
    # ask for a Jira ticket.
    def note_on_case(item)
      @case.messages.create!(
        body: I18n.t("work.escalation.case_note", reference: item.reference, title: item.title),
        kind: :internal_note,
        author: @actor
      )
    end
  end
end
