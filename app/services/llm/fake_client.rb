module Llm
  # Deterministic canned client so the demo and tests run with no model
  # present (handoff §4). Routes on prompt markers emitted by the
  # production prompts — same call sites, plausible outputs.
  class FakeClient
    def chat(messages, json: false, temperature: nil, max_tokens: nil)
      text = messages.map { |m| m[:content] || m["content"] }.join("\n")

      if json && text.include?("[TASK:route]")
        route_response(text)
      elsif json && text.include?("[TASK:draft]")
        draft_response(text)
      elsif json && text.include?("[TASK:sentiment]")
        sentiment_response(text)
      elsif text.include?("[TASK:summarise]")
        "Summary: the citizen reports a service issue; the team has acknowledged it and the case is being processed. Next step: confirm resolution with the citizen."
      elsif text.include?("[TASK:suggest]")
        "Thank you for the details. We have reviewed your case and are taking the following steps to resolve it. We will update you here as soon as the action is complete."
      else
        "Acknowledged."
      end
    end

    private

    def route_response(text)
      queue = text[/QUEUE_OPTIONS:([^\n]*)/, 1].to_s.split(",").map(&:strip).first
      category = text[/CATEGORY_OPTIONS:([^\n]*)/, 1].to_s.split(",").map(&:strip).first
      {
        "queue_slug" => queue,
        "category" => category,
        "priority" => text.match?(/urgent|immediately|emergency/i) ? "high" : "normal",
        "confidence" => 0.9,
        "rationale" => "Keyword match against queue and category descriptions."
      }
    end

    def draft_response(text)
      resolvable = !text.match?(/escalate|complex|legal/i)
      {
        "reply" => "Thank you for raising this. We have looked into your case and the necessary correction has been initiated. You should see it reflected within 3 working days. If you would like to speak to a person at any point, just reply to this message and a staff member will take over.",
        "confidence" => resolvable ? 0.92 : 0.4,
        "fully_resolves" => resolvable,
        "rationale" => "Matched a closed case with the same resolution pattern."
      }
    end

    def sentiment_response(text)
      sentiment =
        if text.match?(/angry|furious|unacceptable|worst|disgusted|outraged/i) then "negative"
        elsif text.match?(/thank|great|resolved|happy|appreciate/i) then "positive"
        else "neutral"
        end
      { "sentiment" => sentiment, "confidence" => 0.85 }
    end
  end
end
