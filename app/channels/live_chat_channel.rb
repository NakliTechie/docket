class LiveChatChannel < ApplicationCable::Channel
  def subscribed
    ActsAsTenant.with_tenant(current_tenant) do
      return reject unless current_tenant.feature?("service_desk.portal")

      live_chat = LiveChat.authenticate(params[:token])
      if live_chat
        stream_for(live_chat)
      else
        reject
      end
    end
  end
end
