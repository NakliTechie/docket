module Api
  module V1
    class CasesController < BaseController
      require_feature "service_desk"
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

      class ContactRequired < StandardError; end

      def create
        # Authorize the primary action BEFORE any on-behalf-of contact is
        # upserted, and do the upsert inside the transaction so a rejected
        # case never leaves an orphaned contact behind (M23).
        authorize_api!(Case.new, :create?, scope: "cases:write")

        kase = Case.transaction do
          contact = resolve_on_behalf_contact! || Contact.find_by(id: params.dig(:case, :contact_id))
          raise ContactRequired if contact.nil?

          k = Case.new(case_params.except(:contact_id))
          k.contact = contact
          k.channel = :api
          k.save!
          create_initial_message(k)
          k
        end
        render json: { data: Serialize.kase(kase.reload, include_messages: true) }, status: :created
      rescue ContactRequired
        render_error("contact_required", status: :unprocessable_entity)
      rescue ActiveRecord::RecordInvalid => e
        render_validation_errors(e.record)
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
        to = params.require(:status)
        # Route through the maker-checker gate, exactly like the web controller
        # and inbound messages — the API (and, via the MCP tool, an agent) must
        # not be the one path that bypasses approval. A guarded target parks and
        # returns false: the transition did NOT happen, so answer 202 with the
        # pending request rather than 200 with an unchanged case.
        if @case.guarded_transition_to(to, requested_by: current_user)
          render json: { data: Serialize.kase(@case) }
        else
          approval = @case.approval_requests.status_pending.recent_first.find_by(requested_action: to.to_s)
          render json: { data: Serialize.kase(@case), approval_request: Serialize.approval_request(approval) },
                 status: :accepted
        end
      end

      def assign
        authorize_api!(@case, :assign?, scope: "cases:write")
        assignee = params[:assignee_id].presence && User.active.find_by(id: params[:assignee_id])
        if params[:assignee_id].present? && assignee.nil? # unknown / inactive / other tenant (L2)
          return render_error("invalid_assignee", detail: "no active user with that id", status: :unprocessable_entity)
        end
        @case.update!(assignee: assignee)
        render json: { data: Serialize.kase(@case) }
      end

      private

      def set_case
        @case = params[:id].to_s.start_with?("DKT-") ? Case.find_by!(tracking_id: params[:id]) : Case.find(params[:id])
      end

      def case_params
        params.require(:case).permit(:subject, :description, :priority, :category_id,
                                     :queue_id, :assignee_id, :contact_id, :sla_policy_id, :lock_version)
      end

      # Body (and any attachments) on create land as the initial inbound
      # message, matching portal/email intake semantics.
      def create_initial_message(kase)
        body = params.dig(:case, :message_body).presence
        attachments = extract_attachments(params[:case])
        return if body.nil? && attachments.empty?
        kase.messages.create!(kind: :public_reply, direction: :inbound,
                              author: kase.contact, body: body || "(attachments)",
                              files: attachments)
      end
    end
  end
end
