module Api
  module V1
    class MessagesController < BaseController
      before_action :set_case

      def index
        authorize_api!(@case, :show?, scope: "cases:read")
        pagy, records = pagy(@case.messages.with_attached_files.order(:created_at))
        render json: { data: records.map { |m| Serialize.message(m) }, pagination: pagination_meta(pagy) }
      end

      def create
        message = @case.messages.build(message_params)
        if current_user
          message.author = current_user
          authorize_api!(message, :create?, scope: nil)
        else
          authorize_api!(message, nil, scope: "cases:write")
          message.author = resolve_on_behalf_contact!
          # Machine-filed citizen messages are inbound; otherwise the
          # integration speaks for the operator (outbound).
          message.direction = message.author ? :inbound : :outbound
        end
        message.direction = :outbound if current_user
        message.files = extract_attachments(params[:message])

        if message.save
          render json: { data: Serialize.message(message) }, status: :created
        else
          render_validation_errors(message)
        end
      end

      private

      def set_case
        @case = params[:case_id].to_s.start_with?("DKT-") ? Case.find_by!(tracking_id: params[:case_id]) : Case.find(params[:case_id])
      end

      def message_params
        permitted = params.require(:message).permit(:body, :kind)
        permitted[:kind] = "public_reply" unless %w[public_reply internal_note].include?(permitted[:kind])
        permitted
      end
    end
  end
end
