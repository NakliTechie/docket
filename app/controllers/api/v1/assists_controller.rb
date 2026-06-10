module Api
  module V1
    # API parity for the staff AI assist (handoff §12: anything the UI
    # can do, an external agent can do).
    class AssistsController < BaseController
      before_action :set_case
      before_action :require_llm!

      def summarise
        authorize_api!(@case, :show?, scope: "cases:read")
        thread = @case.messages.order(:created_at).map { |m| "#{m.author_display_name} (#{m.kind}): #{m.body.truncate(800)}" }.join("\n")
        prompt = "[TASK:summarise]\nSummarise this case thread in 3 sentences or fewer, ending with the next action.\nSubject: #{@case.subject}\nThread:\n#{thread}"
        render json: { data: { summary: client.chat([ { role: "user", content: prompt } ]) } }
      rescue Llm::Error => e
        render_error("llm_failed", detail: e.message, status: :bad_gateway)
      end

      def suggest_reply
        authorize_api!(@case, :update?, scope: "cases:write")
        grounding = Retrieval.grounding_for("#{@case.subject} #{@case.description}")
        prompt = "[TASK:suggest]\nDraft a grounded reply to the citizen.\nSubject: #{@case.subject}\nGrounding:\n#{grounding.map { |g| "- #{g.title}: #{g.text.truncate(600)}" }.join("\n")}"
        render json: { data: { suggestion: client.chat([ { role: "user", content: prompt } ]) } }
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
