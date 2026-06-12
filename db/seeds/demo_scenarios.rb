# Demo scenarios for the sample-data loader. Each scenario is pure DATA the
# shared engine (db/seeds/demo.rb) seeds identically — so docket demos as a
# private-sector product by default (saas), with retail and government as
# alternate verticals. Select with DOCKET_SEED_SCENARIO (default: saas).
#
# Org rows:      [name, kind, external_ref]
# Queue rows:    [name, description]
# Contact rows:  [name, email, phone, external_id, org_index|nil, locale]
# Template rows: ["subject with %s", body, queue_name, category_name, channel]
module DemoScenarios
  SAAS = {
    brand: "Acme Cloud",
    orgs: [
      [ "Acme Cloud Inc.", "company", "ACME-HQ" ],
      [ "Globex Corp", "company", "GLOBEX-77" ],
      [ "Initech LLC", "company", "INITECH-12" ]
    ],
    queues: [
      [ "Technical Support", "Product bugs, errors and how-to" ],
      [ "Billing", "Invoices, plans, refunds" ],
      [ "Onboarding", "New-customer setup and migration" ],
      [ "Account Management", "Renewals, upgrades, escalations" ],
      [ "General", "Everything not yet routed" ]
    ],
    categories: [ "Bug report", "Billing", "Login / SSO", "Integration", "Feature request", "Other" ],
    sla: { standard: "Standard support", priority: "Priority (Enterprise)" },
    kb: [
      [ "Refund policy", "BILL-03: Monthly plans are refundable pro-rata within 14 days of a charge. Annual plans are refundable within 30 days, less any usage above the plan allowance. Refunds return to the original payment method within 5–7 business days." ],
      [ "SSO / SAML setup", "SEC-09: Enterprise plans support SAML 2.0 and OIDC. The customer supplies their IdP metadata URL; we map the email claim to the account. Login issues are usually a clock-skew or audience-mismatch — verify the ACS URL first." ],
      [ "API rate limits", "API-11: Free tier allows 60 requests/min, Pro 600/min, Enterprise 6000/min. A 429 returns a Retry-After header. Sustained overage on Pro is offered an Enterprise upgrade rather than a hard block." ]
    ],
    contacts: [
      [ "Dana Wells", "dana@globex.example", "+14155550101", "GLOBEX-DW", 1, "en" ],
      [ "Marcus Reed", "marcus@initech.example", "+14155550102", "INITECH-MR", 2, "en" ],
      [ "Priya Anand", "priya.anand@example.com", "+919811000201", nil, nil, "en" ],
      [ "Tom Becker", "tom.becker@example.com", nil, nil, nil, "en" ],
      [ "Lena Fischer", "lena@globex.example", "+491701234567", "GLOBEX-LF", 1, "en" ],
      [ "Omar Haddad", "omar.h@example.com", "+971501234567", nil, nil, "en" ],
      [ "Sofia Marino", "sofia.marino@example.com", nil, nil, nil, "en" ],
      [ "Wei Chen", "wei.chen@initech.example", "+8613800138000", "INITECH-WC", 2, "en" ],
      [ "Grace Okafor", "grace.o@example.com", "+2348012345678", nil, nil, "en" ],
      [ "Ivan Petrov", "ivan.p@example.com", nil, nil, nil, "en" ]
    ],
    templates: [
      [ "Login fails with SAML error after %s", "Since the %s change our team can't log in via SSO — it returns an audience-mismatch error. About 40 users are blocked.", "Technical Support", "Login / SSO", :web_portal ],
      [ "Invoice double-charged in %s", "We were billed twice for the %s cycle. Please reverse the duplicate charge on the card ending 4242.", "Billing", "Billing", :email ],
      [ "API returning 429s on the %s plan", "Our integration started getting rate-limited around %s even though we're well under the documented limit. Can you check?", "Technical Support", "Integration", :api ],
      [ "Webhook deliveries stopped after %s", "Webhook events stopped arriving after the %s deploy. Our endpoint is up and returns 200 in tests.", "Technical Support", "Bug report", :api ],
      [ "Migrate data from our old tool by %s", "We're onboarding and need to import ~12k contacts before %s. What's the recommended path?", "Onboarding", "Other", :web_portal ],
      [ "Upgrade quote for %s seats", "We're growing and need pricing to move to %s seats on the Enterprise plan before renewal.", "Account Management", "Billing", :web_portal ],
      [ "Feature request: bulk export for %s", "Could you add a bulk CSV export for %s? Our finance team needs it monthly.", "General", "Feature request", :web_portal ],
      [ "Dashboard slow in the %s region", "The dashboard takes 8–10s to load from %s. It was fine last week.", "Technical Support", "Bug report", :email ]
    ],
    places: [ "the May update", "April", "Pro", "the v3.2", "month-end", "50", "deals", "EU-West", "AP-South", "the weekend" ],
    leads: [
      { name: "Rohan Mehta", email: "rohan.mehta@example.com", company_name: "Mehta Textiles", source: :web_form, status: :new, value_estimate: 45_000 },
      { name: "Anjali Rao", email: "anjali.rao@example.com", company_name: "Rao Logistics", source: :referral, status: :working, value_estimate: 120_000 },
      { name: "Vikram Shah", email: "vikram.shah@example.com", company_name: "Shah Exports", source: :manual, status: :qualified, value_estimate: 87_500 }
    ],
    showcase: [ "Dashboard won't load after the latest update", "Since the update this morning the dashboard is blank for our whole team. Is there an outage?" ]
  }.freeze

  RETAIL = {
    brand: "ShopNova",
    orgs: [
      [ "ShopNova Retail", "company", "SHOPNOVA-HQ" ],
      [ "Metro Wholesale", "company", "METRO-44" ],
      [ "Corner Mart", "company", "CORNER-09" ]
    ],
    queues: [
      [ "Orders", "Order status and changes" ],
      [ "Returns & Refunds", "Returns, exchanges, refunds" ],
      [ "Shipping", "Delivery, tracking, damages" ],
      [ "Payments", "Charges, failed payments, wallets" ],
      [ "General", "Everything not yet routed" ]
    ],
    categories: [ "Order issue", "Return", "Refund", "Shipping delay", "Damaged item", "Other" ],
    sla: { standard: "Standard shopper care", priority: "Priority (wholesale)" },
    kb: [
      [ "Return & exchange policy", "RET-02: Unused items are returnable within 30 days with the order number. Refunds go to the original method within 5–7 days of the item reaching our warehouse. Final-sale and perishable items are non-returnable." ],
      [ "Shipping timelines", "SHIP-05: Standard delivery is 3–5 business days, express 1–2. Tracking activates within 24h of dispatch. Lost-in-transit claims are filed with the carrier after 10 days and a replacement is shipped at no cost." ],
      [ "Damaged-on-arrival handling", "DMG-01: Photograph the item and packaging within 48h and reply on the case. We ship a replacement immediately and arrange a free pickup of the damaged item; no need to wait for the return." ]
    ],
    contacts: [
      [ "Neha Kapoor", "neha.kapoor@example.com", "+919811000301", nil, nil, "en" ],
      [ "Sam Turner", "sam.turner@example.com", "+14155550301", nil, nil, "en" ],
      [ "Priti Desai", "metro@example.com", "+919811000302", "METRO-44", 1, "hi" ],
      [ "Carlos Mendez", "carlos.m@example.com", nil, nil, nil, "en" ],
      [ "Aisha Noor", "aisha.noor@example.com", "+919811000304", nil, nil, "hi" ],
      [ "Greg Palmer", "corner@example.com", "+14155550302", "CORNER-09", 2, "en" ],
      [ "Yuki Tanaka", "yuki.t@example.com", nil, nil, nil, "en" ],
      [ "Mira Sethi", "mira.sethi@example.com", "+919811000307", nil, nil, "en" ],
      [ "Dan O'Brien", "dan.obrien@example.com", "+353851234567", nil, nil, "en" ],
      [ "Fatima Zahra", "fatima.z@example.com", nil, nil, nil, "hi" ]
    ],
    templates: [
      [ "Order %s not delivered", "My order %s was marked delivered but I never received it. The tracking shows no update for 4 days.", "Shipping", "Shipping delay", :web_portal ],
      [ "Wrong item received in order %s", "I ordered a blue jacket (size M) but received a red one (size L) in order %s. I'd like the correct item.", "Returns & Refunds", "Order issue", :email ],
      [ "Refund not received for return %s", "I returned an item two weeks ago (RMA %s) and the refund still hasn't appeared on my card.", "Returns & Refunds", "Refund", :web_portal ],
      [ "Item arrived damaged — order %s", "The package for order %s was crushed and the item inside is broken. Photos attached.", "Shipping", "Damaged item", :email ],
      [ "Payment failed but card was charged for %s", "My payment for %s failed at checkout but the amount was still debited from my account.", "Payments", "Order issue", :api ],
      [ "Cancel order %s before it ships", "Please cancel order %s — I ordered the wrong size and it hasn't shipped yet.", "Orders", "Order issue", :web_portal ],
      [ "Wholesale pricing for %s units", "Metro Wholesale would like a bulk quote for %s units for the festive season.", "General", "Other", :phone ],
      [ "Promo code %s didn't apply", "The code %s wouldn't apply at checkout so I was charged full price. Can you adjust it?", "Payments", "Other", :web_portal ]
    ],
    places: [ "#SN-10472", "#SN-10519", "RMA-3381", "#SN-10588", "#SN-10601", "#SN-10644", "500", "FESTIVE20" ],
    leads: [
      { name: "Raj Malhotra", email: "raj.malhotra@example.com", company_name: "Malhotra Stores", source: :web_form, status: :new, value_estimate: 60_000 },
      { name: "Elena Costa", email: "elena.costa@example.com", company_name: "Costa Grocers", source: :referral, status: :working, value_estimate: 150_000 },
      { name: "Bilal Ahmed", email: "bilal.ahmed@example.com", company_name: "Ahmed Mart", source: :manual, status: :qualified, value_estimate: 95_000 }
    ],
    showcase: [ "Where is my order? Marked delivered but not received", "My order says delivered yesterday but nothing arrived at my address. Can you check with the courier?" ]
  }.freeze

  GOV = {
    brand: "Public Grievance Portal",
    orgs: [
      [ "Directorate of Public Grievances", "department", nil ],
      [ "Bharat National Bank — Karol Bagh Branch", "branch", "BNB-KB-014" ],
      [ "City Jal Board", "department", nil ]
    ],
    queues: [
      [ "Pensions", "Pension and retirement benefit grievances" ],
      [ "Sanitation", "Waste collection and public cleanliness" ],
      [ "Water Supply", "Drinking water and tanker requests" ],
      [ "Banking Services", "Branch customer grievances" ],
      [ "General", "Everything not yet routed" ]
    ],
    categories: [ "Pension delay", "Garbage collection", "Water supply", "Street lighting", "Card services", "Account services", "Other" ],
    sla: { standard: "Standard citizen service", priority: "Priority banking" },
    kb: [
      [ "Pension disbursement SOP", "SOP-PEN-12: Missing or delayed monthly pension credits are reconciled with the disbursing bank within 3 working days. The pensioner is informed on the case thread once the credit is confirmed. Multi-month arrears are escalated to the pension cell with priority high." ],
      [ "Water tanker request procedure", "SOP-WAT-04: Localities reporting supply disruption longer than 24 hours are entitled to a free water tanker, dispatched within 12 hours of verification. Scheduled-maintenance disruptions are announced in advance and do not qualify." ],
      [ "Debit card blocking and unblocking", "SOP-BNK-07: Cards blocked after three wrong PIN attempts unblock automatically after 24 hours. ATM-retained cards return to the branch within 2 working days; collect with ID proof or request a replacement (dispatched within 7 working days)." ]
    ],
    contacts: [
      [ "Asha Rao", "asha.rao@example.com", "+919811000001", nil, 0, "en" ],
      [ "Ravi Kumar", "ravi.kumar@example.com", "+919811000002", "CIF447192", 1, "hi" ],
      [ "Sita Devi", "sita.devi@example.com", nil, nil, nil, "hi" ],
      [ "Mohan Lal", "mohan.lal@example.com", "+919811000004", nil, nil, "en" ],
      [ "Kavita Sharma", "kavita.sharma@example.com", "+919811000005", "CIF447201", 1, "en" ],
      [ "Imran Sheikh", nil, "+919811000006", nil, nil, "hi" ],
      [ "Lakshmi Pillai", "lakshmi.p@example.com", "+919811000007", nil, 2, "en" ],
      [ "Gurpreet Singh", "gurpreet.s@example.com", "+919811000008", "CIF447233", 1, "en" ],
      [ "Anita Desai", "anita.desai@example.com", nil, nil, nil, "en" ],
      [ "Suresh Patil", nil, "+919811000010", nil, nil, "hi" ]
    ],
    templates: [
      [ "Pension not credited for %s", "My monthly pension was not credited this month. Account ending 4521.", "Pensions", "Pension delay", :web_portal ],
      [ "Garbage not collected in %s block", "Waste has not been collected for several days and is piling up near the park gate.", "Sanitation", "Garbage collection", :web_portal ],
      [ "No water supply in %s colony", "There has been no municipal water supply for two days. Children and elderly residents are affected.", "Water Supply", "Water supply", :web_portal ],
      [ "Streetlight broken near %s chowk", "The streetlight has been dark for a week. The stretch is unsafe at night.", "Sanitation", "Street lighting", :email ],
      [ "Debit card blocked after wrong PIN at %s ATM", "My card was blocked after three wrong PIN attempts. I need it urgently for medical payments.", "Banking Services", "Card services", :api ],
      [ "Wrong charges on savings account — %s", "A service charge of Rs 590 was debited twice this quarter. Requesting reversal.", "Banking Services", "Account services", :web_portal ],
      [ "Water tanker request for %s", "Our locality qualifies for a tanker after the pipeline burst. Please dispatch one.", "Water Supply", "Water supply", :phone ],
      [ "Open manhole near %s school", "A manhole cover is missing on the school route. This is dangerous for children.", "Sanitation", "Other", :web_portal ]
    ],
    places: [ "Karol Bagh", "Rajouri Garden", "Mayur Vihar", "Saket", "Dwarka", "Pitampura", "Lajpat Nagar", "Janakpuri" ],
    leads: [
      { name: "Rohan Mehta", email: "rohan.mehta@example.com", company_name: "Mehta Textiles", source: :web_form, status: :new, value_estimate: 45_000 },
      { name: "Anjali Rao", email: "anjali.rao@example.com", company_name: "Rao Logistics", source: :referral, status: :working, value_estimate: 120_000 },
      { name: "Vikram Shah", email: "vikram.shah@example.com", company_name: "Shah Exports", source: :manual, status: :qualified, value_estimate: 87_500 }
    ],
    showcase: [ "Water supply disrupted after pipeline work", "There has been no water in our lane since the pipeline work on Sunday. When will supply resume?" ]
  }.freeze

  ALL = { "saas" => SAAS, "retail" => RETAIL, "gov" => GOV }.freeze

  def self.fetch(name)
    ALL.fetch(name.to_s, SAAS)
  end
end
