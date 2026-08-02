module Portal
  class LiveChatsController < BaseController
    before_action :load_live_chat, only: %i[show message end_chat]

    def new
      @submission = LiveChatSubmission.new(contact: current_contact, preferred_language: I18n.locale.to_s)
    end

    def create
      @submission = LiveChatSubmission.new(submission_params.merge(
        contact: current_contact, preferred_language: I18n.locale.to_s
      ))
      if (result = @submission.save)
        live_chat, raw_token = result
        session[:portal_live_chat_id] = live_chat.id
        session[:portal_live_chat_token] = raw_token
        redirect_to portal_live_chat_path
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @messages = public_messages
      @token = session[:portal_live_chat_token]
    end

    def message
      return render json: { error: t("portal.live_chats.closed") }, status: :unprocessable_entity unless chat_open?

      created = Current.set(actor: @live_chat.contact) do
        @live_chat.case.messages.create(
          kind: :public_reply, direction: :inbound, author: @live_chat.contact,
          body: params[:body]
        )
      end
      if created.persisted?
        @live_chat.keep_alive!
        render json: LiveChatMessageSerializer.call(created), status: :created
      else
        render json: { error: created.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def end_chat
      @live_chat.end! if @live_chat.active?
      session.delete(:portal_live_chat_id)
      session.delete(:portal_live_chat_token)
      redirect_to new_portal_live_chat_path, notice: t("portal.live_chats.ended")
    end

    private

    def load_live_chat
      @live_chat = LiveChat.authenticate(session[:portal_live_chat_token])
      valid = @live_chat&.id == session[:portal_live_chat_id].to_i
      return if valid

      session.delete(:portal_live_chat_id)
      session.delete(:portal_live_chat_token)
      redirect_to new_portal_live_chat_path, alert: t("portal.live_chats.expired")
    end

    def chat_open?
      @live_chat.active? && !@live_chat.case.status_closed?
    end

    def public_messages
      @live_chat.case.messages.where(kind: %i[public_reply agent_turn])
                .includes(:author).order(:created_at)
    end

    def submission_params
      params.require(:live_chat_submission).permit(:name, :email, :phone, :message)
    end
  end
end
