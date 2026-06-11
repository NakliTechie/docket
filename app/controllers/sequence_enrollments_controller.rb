class SequenceEnrollmentsController < ApplicationController
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
    authorize @enrollment.sequence, :enroll?
    @enrollment.cancel!
    redirect_back fallback_location: sequence_path(@enrollment.sequence), notice: t(".cancelled")
  end

  private

  def set_enrollment
    @enrollment = SequenceEnrollment.find(params[:id])
  end

  def find_enrollable
    case params[:enrollable_type]
    when "Lead"    then Lead.find_by(id: params[:enrollable_id])
    when "Contact" then Contact.find_by(id: params[:enrollable_id])
    end
  end
end
