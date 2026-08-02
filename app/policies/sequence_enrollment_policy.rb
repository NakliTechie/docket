class SequenceEnrollmentPolicy < ApplicationPolicy
  def show?
    permit?("pipeline:read") && enrollee_in_scope?(:read)
  end

  def cancel?
    permit?("sequence:enroll") && enrollee_in_scope?(:write)
  end

  class Scope < Scope
    def resolve
      return scope.none unless permit?("pipeline:read")

      leads = RecordVisibility.resolve(user, Lead.with_deleted, access: :read)
      contacts = RecordVisibility.resolve(user, Contact.with_deleted, access: :read)
      lead_rows = scope.where(enrollable_type: "Lead", enrollable_id: leads.select(:id))
      contact_rows = scope.where(enrollable_type: "Contact", enrollable_id: contacts.select(:id))
      lead_rows.or(contact_rows)
    end
  end

  private

  def enrollee_in_scope?(access)
    RecordVisibility.allowed?(user, record.enrollable, access: access)
  end
end
