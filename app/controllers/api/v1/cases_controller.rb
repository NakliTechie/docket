module Api
  module V1
    class CasesController < BaseController
      before_action :set_case, only: %i[show update destroy transition assign]

      def index
        scope = api_scope(Case, scope: "cases:read")
                  .includes(:queue, :category, :contact)
                  .search(params[:q])
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(priority: params[:priority]) if params[:priority].present?
        scope = scope.where(queue_id: params[:queue_id]) if params[:queue_id].present?
        scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
        if params[:contact_external_id].present?
          scope = scope.joins(:contact).where(contacts: { external_id: params[:contact_external_id] })
        end
        scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
        pagy, records = pagy(scope.order(created_at: :desc))
        render json: { data: records.map { |c| Serialize.kase(c) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@case, :show?, scope: "cases:read")
        render json: { data: Serialize.kase(@case, include_messages: params[:include] == "messages") }
      end

      def create
        contact = resolve_on_behalf_contact! || Contact.find_by(id: params.dig(:case, :contact_id))
        authorize_api!(Case.new, :create?, scope: "cases:write")
        return render_error("contact_required", status: :unprocessable_entity) if contact.nil?

        kase = Case.new(case_params.except(:contact_id))
        kase.contact = contact
        kase.channel = :api
        if kase.save
          create_initial_message(kase)
          render json: { data: Serialize.kase(kase.reload, include_messages: true) }, status: :created
        else
          render_validation_errors(kase)
        end
      end

      def update
        authorize_api!(@case, :update?, scope: "cases:write")
        if @case.update(case_params.except(:contact_id))
          render json: { data: Serialize.kase(@case) }
        else
          render_validation_errors(@case)
        end
      end

      def destroy
        authorize_api!(@case, :destroy?, scope: "cases:write")
        if @case.destroy
          head :no_content
        else
          render_validation_errors(@case)
        end
      end

      def transition
        authorize_api!(@case, :transition?, scope: "cases:write")
        @case.transition_to!(params.require(:status))
        render json: { data: Serialize.kase(@case) }
      end

      def assign
        authorize_api!(@case, :assign?, scope: "cases:write")
        assignee = params[:assignee_id].presence && User.active.find(params[:assignee_id])
        @case.update!(assignee: assignee)
        render json: { data: Serialize.kase(@case) }
      end

      private

      def set_case
        @case = params[:id].to_s.start_with?("DKT-") ? Case.find_by!(tracking_id: params[:id]) : Case.find(params[:id])
      end

      def case_params
        params.require(:case).permit(:subject, :description, :priority, :category_id,
                                     :queue_id, :assignee_id, :contact_id, :sla_policy_id)
      end

      # Body on create lands as the initial inbound message, matching
      # portal/email intake semantics.
      def create_initial_message(kase)
        body = params.dig(:case, :message_body).presence
        return unless body
        kase.messages.create!(kind: :public_reply, direction: :inbound,
                              author: kase.contact, body: body)
      end
    end
  end
end
