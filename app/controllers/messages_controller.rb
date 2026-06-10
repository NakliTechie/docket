class MessagesController < ApplicationController
  def create
    @case = Case.find(params[:case_id])
    @message = @case.messages.build(message_params)
    @message.author = Current.user
    @message.direction = :outbound
    authorize @message

    if @message.save
      redirect_to case_path(@case), notice: t(".created")
    else
      redirect_to case_path(@case), alert: @message.errors.full_messages.to_sentence
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
