# Quote lifecycle (Prithvi e2e, Phase 1), each transition attributed to the
# acting user for the hash-chained audit. Build a draft from an issued
# deliverable's scope, send it, then accept (which also advances the deal to
# won so post-sale DealOnboarding can still fire), reject, expire, or revise
# into a new version. Mirrors the Deliverables/ApprovalGate module style.
module Quotes
  Error = Quote::Error

  module_function

  # Seed a draft quote from an issued deliverable: one line per scope entry
  # (description + quantity carried over, price/tax left for the quoter to fill).
  def build_from_deliverable(deliverable, currency:, actor:, valid_until: nil)
    raise Error, "only an issued deliverable can seed a quote" unless deliverable.status_issued?

    Quote.transaction do
      Current.set(actor: actor) do
        quote = Quote.create!(deal: deliverable.deal, deliverable: deliverable,
                              currency: currency, valid_until: valid_until)
        deliverable.scope_entries.each_with_index do |entry, index|
          quote.quote_line_items.create!(description: entry[:description],
                                         quantity: entry[:quantity].presence || 1,
                                         unit_price_cents: 0, tax_rate: 0, position: index)
        end
        quote
      end
    end
  end

  # draft → sent.
  def send!(quote, actor:)
    ensure_status!(quote, "draft", "only a draft quote can be sent")
    raise Error, "a quote needs at least one line before it is sent" unless quote.quote_line_items.exists?

    Current.set(actor: actor) { quote.update!(status: :sent, sent_at: Time.current) }
    quote
  end

  # sent → accepted, and advance the deal to won so DealOnboarding can fire.
  def accept!(quote, actor:)
    ensure_status!(quote, "sent", "only a sent quote can be accepted")
    raise Error, "a superseded quote cannot be accepted" unless quote.latest?
    won = won_stage(quote.deal)

    Quote.transaction do
      Current.set(actor: actor) do
        quote.update!(status: :accepted, accepted_at: Time.current)
        quote.deal.move_to_stage!(won) unless quote.deal.status_won?
      end
    end
    quote
  end

  # sent → rejected.
  def reject!(quote, actor:, reason: nil)
    ensure_status!(quote, "sent", "only a sent quote can be rejected")

    Current.set(actor: actor) do
      quote.update!(status: :rejected, rejected_at: Time.current, rejection_reason: reason.presence)
    end
    quote
  end

  # sent → expired (past its validity).
  def expire!(quote, actor:)
    ensure_status!(quote, "sent", "only a sent quote can expire")
    Current.set(actor: actor) { quote.update!(status: :expired) }
    quote
  end

  # Mint the next version: a new draft sharing +number+, superseding this quote,
  # copying its lines. Not allowed once accepted.
  def revise!(quote, actor:)
    raise Error, "an accepted quote cannot be revised" if quote.status_accepted?

    Quote.transaction do
      Current.set(actor: actor) do
        revision = Quote.create!(deal: quote.deal, deliverable: quote.deliverable,
                                 currency: quote.currency, valid_until: quote.valid_until,
                                 number: quote.number, version: quote.version + 1,
                                 supersedes: quote, notes: quote.notes)
        quote.quote_line_items.each do |line|
          revision.quote_line_items.create!(description: line.description, quantity: line.quantity,
                                            unit_price_cents: line.unit_price_cents, currency: line.currency,
                                            hsn_sac: line.hsn_sac, tax_rate: line.tax_rate, position: line.position)
        end
        revision
      end
    end
  end

  def ensure_status!(quote, expected, message)
    raise Error, message unless quote.status.to_s == expected.to_s
  end

  def won_stage(deal)
    stage = deal.pipeline.pipeline_stages.detect(&:is_won?)
    raise Error, "the deal's pipeline has no won stage to advance to" unless stage
    stage
  end
end
