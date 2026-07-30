# Staff AI assist (handoff §4): thread summarisation and suggested
# replies. Outputs are ephemeral — rendered, never stored — except where
# the staff member commits a suggested reply, which is then noted in
# the message metadata for audit.
class AssistsController < ApplicationController
  # The assist is a service_desk productivity surface (it summarises case threads
  # and drafts replies, shown only inside the case view) — gate it like
  # MessagesController, so a tenant without the service-desk module can't reach
  # it by hitting the URL directly. require_llm still gates on the AI layer.
  require_feature "service_desk"
  before_action :set_case
  before_action :require_llm

  # These run on the request thread (a staff member is waiting), so cap the
  # model wait well below the 120s background default — a slow/stuck model
  # mustn't pin a Puma worker for two minutes (M21). On timeout the rescue
  # renders the friendly assist error.
  INTERACTIVE_READ_TIMEOUT = 25

  def summarise
    authorize @case, :show?
    prompt = AssistPrompts.summarise(@case)

    @summary = client.chat([ { role: "user", content: prompt } ], read_timeout: INTERACTIVE_READ_TIMEOUT)
    render partial: "assists/summary", locals: { summary: @summary, kase: @case }
  rescue Llm::Error => e
    render partial: "assists/error", locals: { message: e.message }, status: :bad_gateway
  end

  def suggest_reply
    authorize @case, :update?
    grounding = Retrieval.grounding_for("#{@case.subject} #{@case.description}")
    prompt = AssistPrompts.suggest_reply(@case, grounding: grounding)

    @suggestion = client.chat([ { role: "user", content: prompt } ], read_timeout: INTERACTIVE_READ_TIMEOUT)
    render partial: "assists/suggestion", locals: { suggestion: @suggestion, kase: @case }
  rescue Llm::Error => e
    # Render into the suggestion frame the button targets, not the default
    # summary frame — otherwise Turbo can't match it and the error is
    # silently swallowed (M31).
    render partial: "assists/error", locals: { message: e.message, frame_id: "assist-suggestion" },
           status: :bad_gateway
  end

  private

  def set_case
    @case = Case.find(params[:case_id])
  end

  def require_llm
    head :not_found if client.nil?
  end

  def client
    @client ||= Llm.client
  end
end
