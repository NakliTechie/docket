class CrmMessagesController < ApplicationController
  require_feature "crm"

  def create
    subject = find_subject
    authorize subject, :update?
    message = CrmMessage.compose(
      subject: subject,
      author: Current.user,
      subject_line: message_params[:subject_line],
      body: message_params[:body]
    )
    redirect_to subject, notice: t("crm_messages.created", recipient: message.recipient_email)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to subject || root_path, alert: error.record.errors.full_messages.to_sentence,
                                     status: :see_other
  end

  private

  def find_subject
    type = params.require(:crm_message).require(:subject_type)
    raise ActiveRecord::RecordNotFound unless CrmMessage::SUBJECT_TYPES.include?(type)

    type.constantize.find(params.require(:crm_message).require(:subject_id))
  end

  def message_params
    params.require(:crm_message).permit(:subject_line, :body)
  end
end
