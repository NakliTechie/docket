# Staff AI assist (handoff §4): thread summarisation and suggested
# replies. Outputs are ephemeral — rendered, never stored — except where
# the staff member commits a suggested reply, which is then noted in
# the message metadata for audit.
class AssistsController < ApplicationController
  before_action :set_case
  before_action :require_llm

  # Bound the summarisation prompt so a very long thread can't blow the
  # model's context window (or its cost): most-recent messages only, with a
  # hard char cap on the joined thread.
  MAX_SUMMARY_MESSAGES = 60
  MAX_SUMMARY_CHARS = 16_000

  def summarise
    authorize @case, :show?
    thread = @case.messages.order(:created_at).last(MAX_SUMMARY_MESSAGES).map { |m|
      "#{m.author_display_name} (#{m.kind}): #{m.body.truncate(800)}"
    }.join("\n").truncate(MAX_SUMMARY_CHARS)
    prompt = <<~PROMPT
      [TASK:summarise]
      Summarise this case thread for a staff member in 3 sentences or fewer, ending with the next required action.
      #{Llm.fence_instruction}
      Subject:
      #{Llm.fence(@case.subject)}
      #{@case.description.presence&.then { |d| "Original request:\n#{Llm.fence(d.truncate(800))}" }}
      Thread:
      #{Llm.fence(thread.presence || "(no messages yet)")}
    PROMPT

    @summary = client.chat([ { role: "user", content: prompt } ])
    render partial: "assists/summary", locals: { summary: @summary, kase: @case }
  rescue Llm::Error => e
    render partial: "assists/error", locals: { message: e.message }, status: :bad_gateway
  end

  def suggest_reply
    authorize @case, :update?
    grounding = Retrieval.grounding_for("#{@case.subject} #{@case.description}")
    last_inbound = @case.messages.where(direction: :inbound).order(:created_at).last
    prompt = <<~PROMPT
      [TASK:suggest]
      Draft a reply for a staff member to send to the citizen. Be concrete, polite, and grounded ONLY in the context provided. Do not invent case facts.
      #{Llm.fence_instruction}
      Subject:
      #{Llm.fence(@case.subject)}
      Original request:
      #{Llm.fence(@case.description.presence || @case.messages.where(direction: :inbound).order(:created_at).first&.body || "")}
      Latest citizen message:
      #{Llm.fence(last_inbound&.body&.truncate(1500) || "(none)")}
      Grounding:
      #{grounding.map { |g| "- #{g.title}: #{g.text.truncate(600)}" }.join("\n").presence || "(none)"}
      Reply with the message text only.
    PROMPT

    @suggestion = client.chat([ { role: "user", content: prompt } ])
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
