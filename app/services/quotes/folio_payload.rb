module Quotes
  # Serializes an ACCEPTED quote into the payload folio's inbound
  # accepted-quote→invoice endpoint (F-1) will consume. Docket does NOT post to
  # folio here — this is the shape only; the S-1 seam performs the signed,
  # idempotent push. The party is folio's "party" handle (Contact#external_id),
  # presence-guarded. The idempotency key is quote id + version + party, so a
  # resend is a no-op on folio's side. The payload rides in the request BODY
  # only (never the URL).
  module FolioPayload
    Error = Class.new(StandardError)

    module_function

    def build(quote)
      raise Error, "only an accepted quote can be sent to billing" unless quote.status_accepted?
      party = quote.deal.contact&.external_id.presence
      raise Error, "the deal's contact needs an external_id (the folio party handle)" unless party

      {
        source_system: "docket",
        quote_ref: quote.reference,
        quote_id: quote.id,
        version: quote.version,
        idempotency_key: idempotency_key(quote, party),
        party_external_id: party,
        currency: quote.currency,
        billing_type: quote.billing_type,
        lines: quote.quote_line_items.map { |line| line_payload(line) },
        totals: {
          subtotal_cents: quote.subtotal_cents,
          tax_cents: quote.tax_cents,
          total_cents: quote.total_cents
        },
        milestones: milestones_payload(quote)
      }
    end

    def idempotency_key(quote, party)
      "docket:quote:#{quote.id}:v#{quote.version}:#{party}"
    end

    def line_payload(line)
      {
        description: line.description,
        quantity: line.quantity.to_s,
        unit_price_cents: line.unit_price_cents,
        currency: line.currency,
        hsn_sac: line.hsn_sac,
        tax_rate: line.tax_rate.to_s,
        tax_amount_cents: line.tax_amount_cents,
        total_cents: line.total_cents
      }
    end

    def milestones_payload(quote)
      return [] unless quote.billing_type_milestone?

      milestones = quote.quote_milestones.to_a
      raise Error, "a milestone-billed quote needs a milestone schedule" if milestones.empty?
      unless quote.milestones_balanced?
        raise Error, "the milestone schedule must reconcile to the quote total (#{quote.total_cents})"
      end

      amounts = quote.milestone_amounts
      milestones.map do |milestone|
        {
          name: milestone.name,
          amount_cents: amounts.fetch(milestone.id),
          due_on: milestone.due_on,
          trigger: milestone.trigger,
          position: milestone.position
        }
      end
    end
  end
end
