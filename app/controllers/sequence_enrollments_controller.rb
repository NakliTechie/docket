class SequenceEnrollmentsController < ApplicationController
  require_feature "crm.sequences"
  before_action :set_enrollment, only: %i[cancel]

  def create
    sequence = Sequence.find(params[:sequence_id])
    authorize sequence, :enroll?
    target = find_enrollable
    if target
      sequence.enroll!(target)
      redirect_back fallback_location: sequence_path(sequence), notice: t(".enrolled")
    else
      redirect_back fallback_location: sequence_path(sequence), alert: t(".enroll_failed")
    end
  end

  def cancel
    authorize @enrollment, :cancel?
    @enrollment.cancel!
    redirect_back fallback_location: sequence_path(@enrollment.sequence), notice: t(".cancelled")
  end

  private

  def set_enrollment
    @enrollment = policy_scope(SequenceEnrollment).find(params[:id])
  end

  def find_enrollable
    case params[:enrollable_type]
    when "Lead"    then writable_scope(Lead).find_by(id: params[:enrollable_id])
    when "Contact" then writable_scope(Contact).find_by(id: params[:enrollable_id])
    end
  end

  def writable_scope(model)
    RecordVisibility.resolve(Current.user, model.all, access: :write)
  end
end
