class MessagesController < ApplicationController
  def create
    @case = Case.find(params[:case_id])
    @message = @case.messages.build(message_params)
    @message.author = Current.user
    @message.direction = :outbound
    metadata = {}
    if (macro = Macro.find_by(id: params[:macro_id]))
      metadata.merge!("macro_id" => macro.id, "macro_name" => macro.name)
    end
    # Suggested-reply usage is noted for audit (handoff §4).
    metadata["ai_suggested"] = true if params[:ai_suggested] == "true"
    @message.metadata = metadata.presence
    authorize @message

    if @message.save
      redirect_to case_path(@case), notice: t(".created")
    else
      # Preserve the typed reply so a save failure (e.g. a rejected
      # attachment) doesn't discard it (M30). Attachments can't survive a
      # round-trip (browser security), but the text can.
      redirect_to case_path(@case),
                  alert: @message.errors.full_messages.to_sentence,
                  flash: { compose_body: @message.body }
    end
  end

  private

  def message_params
    permitted = params.require(:message).permit(:body, :kind, files: [])
    # Staff compose only replies or notes; agent turns are machine-created.
    permitted[:kind] = "public_reply" unless %w[public_reply internal_note].include?(permitted[:kind])
    permitted
  end
end
