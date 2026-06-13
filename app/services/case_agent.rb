# The agentic resolution loop (handoff §4). Three gated actions:
#   route   — classify queue/category/priority (always on when AI is on)
#   draft   — propose a reply for human review (default)
#   resolve — send + resolve autonomously (per-category opt-in, earned)
# Every step is logged on the case as a Message carrying the full
# prompt/response in metadata. The agent never edits or deletes
# anything, and every public reply offers a human handoff.
class CaseAgent
  ROUTE_CONFIDENCE_DEFAULT = 0.5
  RESOLVE_CONFIDENCE_DEFAULT = 0.85

  attr_reader :kase, :client

  def initialize(kase, client: Llm.client)
    @kase = kase
    @client = client
  end

  def run
    return if client.nil? || !kase.status_new?

    route_result = route
    draft_result = draft if Setting.get("ai_draft_enabled", true)
    return if draft_result.nil?

    if auto_resolve?(draft_result)
      resolve(draft_result)
    end
  rescue Llm::Error => e
    log_failure(e)
  end

  private

  def route
    # A declarative routing rule already classified this case — keep its routing,
    # skip the LLM classification, just complete triage.
    if kase.routed_by_rule_id.present?
      kase.transition_to!(:triaged) if kase.status_new?
      return { "routed_by" => "rule", "rule_id" => kase.routed_by_rule_id }
    end

    prompt = <<~PROMPT
      [TASK:route]
      You triage citizen grievances for a public service desk. Classify the case below.
      #{Llm.fence_instruction}
      QUEUE_OPTIONS:#{CaseQueue.order(:name).pluck(:slug).join(", ")}
      CATEGORY_OPTIONS:#{Category.order(:name).pluck(:name).join(", ")}
      PRIORITY_OPTIONS:low, normal, high, urgent

      Case subject:
      #{Llm.fence(kase.subject)}
      Case body:
      #{Llm.fence(initial_body)}

      Respond with JSON: {"queue_slug": ..., "category": ..., "priority": ..., "confidence": 0.0-1.0, "rationale": ...}
    PROMPT

    result = hash_result(client.chat([ { role: "user", content: prompt } ], json: true))
    apply_routing(result) if result["confidence"].to_f >= threshold("ai_route_confidence", ROUTE_CONFIDENCE_DEFAULT)
    log_turn("route", prompt, result)
    result
  end

  def apply_routing(result)
    queue = CaseQueue.find_by(slug: result["queue_slug"].to_s)
    category = Category.find_by(name: result["category"].to_s)
    priority = result["priority"].to_s.presence_in(Case.priorities.keys)

    kase.update!({
      queue: queue || kase.queue,
      category: category || kase.category,
      priority: priority || kase.priority
    })
    kase.transition_to!(:triaged)
  end

  def draft
    grounding = Retrieval.grounding_for("#{kase.subject} #{initial_body}")
    prompt = <<~PROMPT
      [TASK:draft]
      You resolve tier-1 citizen cases for a public service desk. Use ONLY the grounding context; if it does not contain the answer, say a staff member will follow up and set fully_resolves to false. Always tell the citizen they can reply to reach a human.
      #{Llm.fence_instruction}

      Case subject:
      #{Llm.fence(kase.subject)}
      Case body:
      #{Llm.fence(initial_body)}

      Grounding context:
      #{grounding.map { |g| "- (#{g.source}) #{g.title}: #{g.text}" }.join("\n").presence || "(none)"}

      Respond with JSON: {"reply": ..., "confidence": 0.0-1.0, "fully_resolves": true/false, "rationale": ...}
    PROMPT

    result = hash_result(client.chat([ { role: "user", content: prompt } ], json: true))
    log_turn("draft", prompt, result, body: result["reply"])
    result
  end

  def auto_resolve?(draft_result)
    kase.category&.ai_auto_resolve &&
      draft_result["fully_resolves"] == true &&
      draft_result["confidence"].to_f >= threshold("ai_resolve_confidence", RESOLVE_CONFIDENCE_DEFAULT)
  end

  def resolve(draft_result)
    # Auto-resolve is gated on the DRAFT confidence, independently of
    # routing — so it can fire on a case that routing left as `new` (low
    # route confidence). `new` can't transition straight to `resolved`, so
    # move it through a valid intermediate state FIRST. Doing this before
    # creating the public reply means we never email the citizen and then
    # raise InvalidTransition, leaving the case stuck (M19).
    kase.reload
    kase.transition_to!(:triaged) if kase.status_new?

    kase.messages.create!(
      kind: :agent_turn,
      direction: :outbound,
      author: nil,
      body: "#{draft_result["reply"]}\n\n#{I18n.t("cases.agent.human_handoff_footer")}",
      metadata: { "ai" => "resolve", "confidence" => draft_result["confidence"],
                  "rationale" => draft_result["rationale"] }
    )
    kase.reload.transition_to!(:resolved)
  end

  # Route/draft working turns are internal notes (staff-only); only
  # resolve sends a public agent_turn.
  def log_turn(action, prompt, result, body: nil)
    kase.messages.create!(
      kind: :internal_note,
      direction: :outbound,
      author: nil,
      body: body.presence || I18n.t("cases.agent.turn_note", action: action),
      metadata: { "ai" => action, "prompt" => prompt, "response" => result,
                  "confidence" => result["confidence"] }
    )
  end

  def log_failure(error)
    kase.messages.create!(
      kind: :internal_note, direction: :outbound, author: nil,
      body: I18n.t("cases.agent.failed"),
      metadata: { "ai" => "error", "error" => error.message }
    )
  end

  def initial_body
    kase.description.presence || kase.messages.where(direction: :inbound).order(:created_at).first&.body.to_s
  end

  def threshold(key, default)
    Setting.get(key, default).to_f
  end

  # A model can return valid JSON that isn't an object (an array, a bare
  # string/number). Coerce to {} so the result["confidence"]/["reply"]
  # accessors degrade to nil instead of raising and killing the job.
  def hash_result(result)
    result.is_a?(Hash) ? result : {}
  end
end
