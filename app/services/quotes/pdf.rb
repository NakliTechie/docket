require "prawn"
require "prawn/table"

module Quotes
  # Renders a Quote to a PDF document (bytes): header, the deal it's for, a line
  # table (description, HSN/SAC, qty, unit price, tax %, tax, line total),
  # totals, and the deliverable it derives from. Pure Prawn — no native
  # extensions, no network, no headless browser (sovereignty-safe).
  module Pdf
    module_function

    def render(quote)
      currency = quote.currency
      Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
        pdf.text "Quotation #{quote.reference}", size: 18, style: :bold
        pdf.move_down 4
        pdf.text "Status: #{quote.human_status}"
        pdf.text "Deal: #{quote.deal.name}"
        pdf.text "Valid until: #{quote.valid_until}" if quote.valid_until
        pdf.text "Derived from deliverable: #{quote.deliverable.title}", size: 9, style: :italic if quote.deliverable
        pdf.move_down 12

        header = [ "Description", "HSN/SAC", "Qty", "Unit price", "Tax %", "Tax", "Line total" ]
        rows = quote.quote_line_items.map do |line|
          [ line.description, line.hsn_sac.to_s, format_quantity(line.quantity),
            money(line.unit_price_cents, currency), format_rate(line.tax_rate),
            money(line.tax_amount_cents, currency), money(line.total_cents, currency) ]
        end
        pdf.table([ header ] + rows, header: true, width: pdf.bounds.width) do
          row(0).font_style = :bold
          columns(2..6).align = :right
        end

        pdf.move_down 12
        pdf.text "Subtotal: #{money(quote.subtotal_cents, currency)}", align: :right
        pdf.text "Tax: #{money(quote.tax_cents, currency)}", align: :right
        pdf.text "Total: #{money(quote.total_cents, currency)}", size: 13, style: :bold, align: :right
      end.render
    end

    def money(cents, currency)
      "#{currency} #{format('%.2f', cents.to_i / 100.0)}"
    end

    def format_quantity(quantity)
      quantity == quantity.to_i ? quantity.to_i.to_s : quantity.to_s
    end

    def format_rate(rate)
      rate == rate.to_i ? "#{rate.to_i}%" : "#{rate}%"
    end
  end
end
