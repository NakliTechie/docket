require "test_helper"

class CrmDepthTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "configured web-to-lead mapping records form and consent provenance" do
    form = LeadCaptureForm.create!(
      name: "Partner landing", slug: "partner", active: true, is_default: true,
      consent_disclosure: "Partner campaign opt-in",
      field_mapping: { "full_name" => "name", "work_email" => "email",
                       "organisation" => "company_name", "question" => "notes" }
    )

    assert_difference "Lead.count", 1 do
      post lead_capture_path(form.slug), params: { lead_inquiry: {
        fields: { full_name: "Mapped Prospect", work_email: "mapped@example.com",
                  organisation: "Mapped Co", question: "Need a pilot" },
        email_consent: "1", sms_consent: "0"
      } }
    end

    assert_response :created
    lead = Lead.order(:id).last
    assert_equal "Mapped Prospect", lead.name
    assert_equal "Mapped Co", lead.company_name
    assert_equal "Need a pilot", lead.notes
    assert lead.email_consent?
    refute lead.sms_consent?
    assert lead.consent_captured_at?
    assert_equal "web:partner", lead.consent_source
    assert_equal form.id, lead.provenance["capture_form_id"]
    assert lead.provenance["request_id"].present?
  end

  test "changing the default capture form audits the displaced default" do
    original = LeadCaptureForm.create!(
      name: "Original default", slug: "original-default", active: true, is_default: true,
      field_mapping: { "name" => "name", "email" => "email" }
    )

    LeadCaptureForm.create!(
      name: "New default", slug: "new-default", active: true, is_default: true,
      field_mapping: { "name" => "name", "email" => "email" }
    )

    refute original.reload.is_default?
    entry = AuditEntry.where(action: "lead_capture_form.update",
                             auditable_type: "LeadCaptureForm", auditable_id: original.id).last
    assert_equal [ true, false ], entry.changeset["is_default"]
  end

  test "duplicate review is exact and merge preserves lineage and moves deals" do
    CustomFieldDefinition.create!(resource_type: "leads", key: "account_tier", label: "Account tier",
                                  field_type: :short_text)
    CustomFieldDefinition.create!(resource_type: "leads", key: "territory", label: "Territory",
                                  field_type: :short_text)
    target = Lead.create!(name: "Canonical", email: "same@example.com", notes: "Target",
                          custom_fields: { account_tier: "Platinum" })
    source = Lead.create!(name: "Duplicate", email: "SAME@example.com", notes: "Source",
                          email_consent: true, consent_captured_at: 1.day.ago,
                          provenance: { "channel" => "web_form" },
                          custom_fields: { account_tier: "Gold", territory: "West" })
    unrelated = Lead.create!(name: "Similar name", email: "different@example.com")
    deal = Deal.create!(name: "Duplicate deal", pipeline: pipelines(:sales), lead: source)

    assert_includes LeadDuplicateFinder.call(target), source
    refute_includes LeadDuplicateFinder.call(target), unrelated

    post merge_lead_path(target), params: { source_lead_id: source.id }

    assert_redirected_to lead_path(target)
    assert_equal target, source.reload.merged_into
    assert_equal target, source.canonical_record
    assert_equal target, deal.reload.lead
    assert target.reload.email_consent?
    assert_includes target.notes, "Target"
    assert_includes target.notes, "Source"
    assert_includes target.provenance["merged_lead_ids"], source.id
    assert_equal "Platinum", target.custom_fields.fetch("account_tier")
    assert_equal "West", target.custom_fields.fetch("territory")

    get lead_path(source)
    assert_response :success
    assert_select "h1", text: /Canonical/
  end

  test "deal products derive one currency-correct total and reject a mismatched catalog" do
    deal = Deal.create!(name: "Priced deal", pipeline: pipelines(:sales), currency: "INR")
    product = Product.create!(name: "Platform", sku: "PLAT", default_unit_price: "1250.50",
                              currency: "INR")

    post deal_line_items_path(deal), params: { deal_line_item: {
      product_id: product.id, quantity: "2"
    } }
    assert_redirected_to deal_path(deal)
    item = deal.deal_line_items.find_by!(product: product)
    assert_equal 250_100, item.total_cents
    assert_equal 250_100, deal.reload.value_cents
    total_audit = AuditEntry.where(action: "deal.update", auditable_type: "Deal",
                                   auditable_id: deal.id).last
    assert_equal [ nil, 250_100 ], total_audit.changeset["value_cents"]

    usd = Product.create!(name: "USD service", sku: "USD", default_unit_price: 10, currency: "USD")
    assert_no_difference "DealLineItem.count" do
      post deal_line_items_path(deal), params: { deal_line_item: { product_id: usd.id, quantity: 1 } }
    end
    assert_response :see_other

    deal.currency = "USD"
    refute deal.valid?
    assert_includes deal.errors[:currency], "cannot change while the deal has line items"
  end

  test "competitor outcomes appear in loss reporting and CSV" do
    competitor = Competitor.create!(name: "Rival One", website: "https://rival.example")
    deal = Deal.create!(name: "Lost account", pipeline: pipelines(:sales),
                        pipeline_stage: pipeline_stages(:sales_lost), value: 5000, currency: "INR")
    DealCompetitor.create!(deal: deal, competitor: competitor, disposition: :lost_to)

    report = SalesReport.new(from: Date.current - 1, to: Date.current + 1)
    row = report.competitor_losses.find { |candidate| candidate[:competitor] == competitor }
    assert_equal 1, row[:count]
    assert_equal 500_000, row[:value_cents]
    assert_includes report.to_csv, "competitor_loss,Rival One,1,5000.0,INR"

    get sales_report_path
    assert_response :success
    assert_includes response.body, "Rival One"
  end

  test "competitor websites require one complete HTTP URL value" do
    competitor = Competitor.new(name: "Unsafe URL", website: "https://safe.example\njavascript:alert(1)")

    refute competitor.valid?
    assert competitor.errors[:website].present?
  end
end
