module Api
  module V1
    # API parity for the staff AI assist (handoff §12: anything the UI
    # can do, an external agent can do).
    class AssistsController < BaseController
      # Same service_desk gate as the web assist — an API token for a tenant
      # without the service-desk module gets 403 feature_disabled, not AI over
      # its cases.
      require_feature "service_desk"
      before_action :set_case
      before_action :require_llm!

      INTERACTIVE_READ_TIMEOUT = 25

      def summarise
        authorize_api!(@case, :show?, scope: "cases:read")
        prompt = AssistPrompts.summarise(@case)
        render json: { data: { summary: client.chat([ { role: "user", content: prompt } ], read_timeout: INTERACTIVE_READ_TIMEOUT) } }
      rescue Llm::Error => e
        render_error("llm_failed", detail: e.message, status: :bad_gateway)
      end

      def suggest_reply
        authorize_api!(@case, :update?, scope: "cases:write")
        grounding = Retrieval.grounding_for("#{@case.subject} #{@case.description}")
        prompt = AssistPrompts.suggest_reply(@case, grounding: grounding)
        render json: { data: { suggestion: client.chat([ { role: "user", content: prompt } ], read_timeout: INTERACTIVE_READ_TIMEOUT) } }
      rescue Llm::Error => e
        render_error("llm_failed", detail: e.message, status: :bad_gateway)
      end

      private

      def set_case
        @case = Case.find(params[:case_id])
      end

      def require_llm!
        render_error("ai_disabled", status: :not_found) if client.nil?
      end

      def client
        @client ||= Llm.client
      end
    end
  end
end
