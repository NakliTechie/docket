# Staff AI assist (handoff §4): thread summarisation and suggested
# replies. Outputs are ephemeral — rendered, never stored — except where
# the staff member commits a suggested reply, which is then noted in
# the message metadata for audit.
class AssistsController < ApplicationController
  before_action :set_case
  before_action :require_llm

  def summarise
    authorize @case, :show?
    thread = @case.messages.order(:created_at).map { |m|
      "#{m.author_display_name} (#{m.kind}): #{m.body.truncate(800)}"
    }.join("\n")
    prompt = <<~PROMPT
      [TASK:summarise]
      Summarise this case thread for a staff member in 3 sentences or fewer, ending with the next required action.
      Subject: #{@case.subject}
      #{@case.description.presence&.then { |d| "Original request: #{d.truncate(800)}" }}
      Thread:
      #{thread.presence || "(no messages yet)"}
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
      Subject: #{@case.subject}
      Original request: #{@case.description.presence || @case.messages.where(direction: :inbound).order(:created_at).first&.body}
      Latest citizen message: #{last_inbound&.body&.truncate(1500)}
      Grounding:
      #{grounding.map { |g| "- #{g.title}: #{g.text.truncate(600)}" }.join("\n").presence || "(none)"}
      Reply with the message text only.
    PROMPT

    @suggestion = client.chat([ { role: "user", content: prompt } ])
    render partial: "assists/suggestion", locals: { suggestion: @suggestion, kase: @case }
  rescue Llm::Error => e
    render partial: "assists/error", locals: { message: e.message }, status: :bad_gateway
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
