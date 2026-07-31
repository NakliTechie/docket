class MessagesController < ApplicationController
  require_feature "service_desk"
  def create
    @case = Case.find(params[:case_id])
    @message = @case.messages.build(message_params)
    @message.author = Current.user
    @message.direction = :outbound
    metadata = {}
    if (macro = Macro.find_by(id: params[:macro_id]))
      metadata.merge!("macro_id" => macro.id, "macro_name" => macro.name,
                      "macro_actions" => macro.actions_summary)
      @message.kind = macro.message_kind if macro.message_kind.present?
    end
    # Suggested-reply usage is noted for audit (handoff §4).
    metadata["ai_suggested"] = true if params[:ai_suggested] == "true"
    if @message.kind_public_reply? && Current.user.email_signature.present?
      metadata["signature"] = Current.user.email_signature
    end
    @message.metadata = metadata.presence
    authorize @message

    saved = Message.transaction do
      @message.save! if @message.valid?
      macro&.apply_to!(@case, requested_by: Current.user) if @message.persisted?
      @message.persisted?
    end
    if saved
      redirect_to case_path(@case), notice: t(".created")
    else
      # Preserve the typed reply so a save failure (e.g. a rejected
      # attachment) doesn't discard it (M30). Attachments can't survive a
      # round-trip (browser security), but the text can.
      redirect_to case_path(@case),
                  alert: @message.errors.full_messages.to_sentence,
                  flash: { compose_body: @message.body }
    end
  rescue ActiveRecord::RecordInvalid, Case::InvalidTransition => error
    @message.errors.add(:base, error.message) if @message.errors.empty?
    redirect_to case_path(@case), alert: @message.errors.full_messages.to_sentence,
                flash: { compose_body: @message.body }
  end

  private

  def message_params
    permitted = params.require(:message).permit(:body, :kind, files: [])
    # Staff compose only replies or notes; agent turns are machine-created.
    permitted[:kind] = "public_reply" unless %w[public_reply internal_note].include?(permitted[:kind])
    permitted
  end
end
