# Demo dataset (handoff G4): a fictional "Directorate of Public
# Grievances" plus a fictional public-sector bank branch. ~8 staff,
# ~60 cases across every status and channel, KB docs, macros, SLA
# policies. Idempotent via the demo_seeded marker. All names and data
# are fictional.
return if Setting.get("demo_seeded")

rng = Random.new(42)
puts "Seeding demo data…"

Current.set(actor: nil) do
  # --- Settings / AI demo mode -------------------------------------------
  Setting.set("llm_provider", "fake")
  Setting.set("ai_draft_enabled", true)

  # --- Organisations ------------------------------------------------------
  dpg = Organisation.find_or_create_by!(name: "Directorate of Public Grievances") { |o| o.kind = "department" }
  bank = Organisation.find_or_create_by!(name: "Bharat National Bank — Karol Bagh Branch") do |o|
    o.kind = "branch"
    o.external_ref = "BNB-KB-014"
  end
  jal = Organisation.find_or_create_by!(name: "City Jal Board") { |o| o.kind = "department" }

  # --- Queues ---------------------------------------------------------------
  queues = {}
  [ [ "Pensions", "Pension and retirement benefit grievances" ],
    [ "Sanitation", "Waste collection and public cleanliness" ],
    [ "Water Supply", "Drinking water and tanker requests" ],
    [ "Banking Services", "Branch customer grievances" ],
    [ "General", "Everything not yet routed" ] ].each do |name, description|
    queues[name] = CaseQueue.find_or_create_by!(name: name) { |q| q.description = description }
  end

  # --- Users (8 staff + seeded admin keeps working) -------------------------
  password = ENV.fetch("DOCKET_DEMO_PASSWORD", "docket-demo")
  users = {}
  [ [ "Arjun Mehta", "arjun@docket.local", :admin, %w[General] ],
    [ "Sunita Rao", "sunita@docket.local", :supervisor, %w[Pensions General] ],
    [ "Vikram Joshi", "vikram@docket.local", :supervisor, %w[Banking\ Services] ],
    [ "Priya Nair", "priya@docket.local", :agent, %w[Pensions] ],
    [ "Rohan Gupta", "rohan@docket.local", :agent, %w[Sanitation Water\ Supply] ],
    [ "Fatima Khan", "fatima@docket.local", :agent, %w[Banking\ Services] ],
    [ "Deepak Yadav", "deepak@docket.local", :agent, %w[Water\ Supply General] ],
    [ "Meena Iyer", "meena@docket.local", :readonly, [] ] ].each do |name, email, role, queue_names|
    user = User.find_or_create_by!(email_address: email) do |u|
      u.name = name
      u.role = role
      u.password = password
    end
    queue_names.each do |qn|
      QueueMembership.find_or_create_by!(user: user, queue: queues[qn])
    end
    users[name] = user
  end

  # --- Categories ------------------------------------------------------------
  categories = {}
  [ "Pension delay", "Garbage collection", "Water supply", "Street lighting",
    "Card services", "Account services", "Other" ].each do |name|
    categories[name] = Category.find_or_create_by!(name: name)
  end

  # --- SLA policies -----------------------------------------------------------
  standard = SlaPolicy.find_or_create_by!(name: "Standard citizen service") do |p|
    p.description = "Default targets for public grievances"
  end
  if standard.sla_targets.empty?
    [ [ :low, 480, 10080 ], [ :normal, 240, 4320 ], [ :high, 60, 1440 ], [ :urgent, 30, 480 ] ].each do |priority, fr, res|
      standard.sla_targets.create!(priority: priority, first_response_minutes: fr, resolution_minutes: res)
    end
  end
  banking = SlaPolicy.find_or_create_by!(name: "Priority banking") do |p|
    p.description = "Tighter targets for bank customer grievances"
  end
  if banking.sla_targets.empty?
    [ [ :low, 240, 4320 ], [ :normal, 120, 1440 ], [ :high, 30, 480 ], [ :urgent, 15, 240 ] ].each do |priority, fr, res|
      banking.sla_targets.create!(priority: priority, first_response_minutes: fr, resolution_minutes: res)
    end
  end
  Setting.set("default_sla_policy_id", standard.id)
  Setting.set("default_queue_id", queues["General"].id)

  # --- Macros ------------------------------------------------------------------
  [ [ "Acknowledgement",
      "Dear {{contact_name}},\n\nYour case {{tracking_id}} has been received and is with our {{queue_name}} team. We will update you here.\n\nRegards,\n{{agent_name}}" ],
    [ "More information needed",
      "Dear {{contact_name}},\n\nTo proceed with case {{tracking_id}} we need a few more details from you. Please reply to this message with the requested information.\n\nRegards,\n{{agent_name}}" ],
    [ "Resolution confirmation",
      "Dear {{contact_name}},\n\nCase {{tracking_id}} has been resolved. If the issue recurs, simply reply and the case will be reopened.\n\nRegards,\n{{agent_name}}" ] ].each do |name, body|
    Macro.find_or_create_by!(name: name) { |m| m.body = body }
  end

  # --- Reference docs (AI grounding) ---------------------------------------------
  [ [ "Pension disbursement SOP",
      "SOP-PEN-12: Missing or delayed monthly pension credits are reconciled with the disbursing bank within 3 working days of the complaint. The pensioner is informed on the case thread once the credit is confirmed. Arrears for multiple months are escalated to the directorate's pension cell with priority high." ],
    [ "Water tanker request procedure",
      "SOP-WAT-04: Localities reporting supply disruption longer than 24 hours are entitled to a free water tanker. Tankers are dispatched within 12 hours of verification. Disruptions caused by scheduled maintenance are announced in advance and do not qualify." ],
    [ "Debit card blocking and unblocking",
      "SOP-BNK-07: Cards blocked after three wrong PIN attempts unblock automatically after 24 hours. Cards retained by an ATM are returned to the issuing branch within 2 working days; the customer may collect with ID proof, or request a replacement which is dispatched within 7 working days." ],
    [ "Grievance escalation matrix",
      "ESC-01: Cases breaching their resolution SLA are escalated to the queue supervisor. A second breach escalates to the directorate. Citizens may request escalation at any time by replying on their case; staff record the request as an internal note and reassign." ] ].each do |title, body|
    ReferenceDoc.find_or_create_by!(title: title) { |d| d.body = body }
  end

  # --- Contacts -----------------------------------------------------------------
  citizens = [
    [ "Asha Rao", "asha.rao@example.com", "+919811000001", nil, dpg, "en" ],
    [ "Ravi Kumar", "ravi.kumar@example.com", "+919811000002", "CIF447192", bank, "hi" ],
    [ "Sita Devi", "sita.devi@example.com", nil, nil, nil, "hi" ],
    [ "Mohan Lal", "mohan.lal@example.com", "+919811000004", nil, nil, "en" ],
    [ "Kavita Sharma", "kavita.sharma@example.com", "+919811000005", "CIF447201", bank, "en" ],
    [ "Imran Sheikh", nil, "+919811000006", nil, nil, "hi" ],
    [ "Lakshmi Pillai", "lakshmi.p@example.com", "+919811000007", nil, jal, "en" ],
    [ "Gurpreet Singh", "gurpreet.s@example.com", "+919811000008", "CIF447233", bank, "en" ],
    [ "Anita Desai", "anita.desai@example.com", nil, nil, nil, "en" ],
    [ "Suresh Patil", nil, "+919811000010", nil, nil, "hi" ],
    [ "Farida Begum", "farida.b@example.com", "+919811000011", nil, nil, "hi" ],
    [ "Nikhil Verma", "nikhil.v@example.com", "+919811000012", "CIF447250", bank, "en" ],
    [ "Pooja Reddy", "pooja.reddy@example.com", "+919811000013", nil, nil, "en" ],
    [ "Abdul Rahman", "abdul.r@example.com", "+919811000014", nil, nil, "hi" ],
    [ "Geeta Joshi", nil, "+919811000015", nil, nil, "hi" ],
    [ "Harish Chandra", "harish.c@example.com", "+919811000016", nil, dpg, "en" ],
    [ "Rekha Menon", "rekha.menon@example.com", "+919811000017", "CIF447261", bank, "en" ],
    [ "Vijay Saxena", "vijay.s@example.com", "+919811000018", nil, nil, "en" ],
    [ "Shabnam Ali", "shabnam.ali@example.com", nil, nil, nil, "hi" ],
    [ "Dinesh Kamble", nil, "+919811000020", nil, nil, "en" ]
  ].map do |name, email, phone, cif, org, lang|
    Contact.find_or_create_by!(name: name) do |c|
      c.email = email
      c.phone = phone
      c.external_id = cif
      c.organisation = org
      c.preferred_language = lang
    end
  end

  # --- Cases -----------------------------------------------------------------------
  templates = [
    [ "Pension not credited for %s", "My monthly pension was not credited this month. Account ending 4521.", "Pensions", "Pension delay", :web_portal ],
    [ "Garbage not collected in %s block", "Waste has not been collected for several days and is piling up near the park gate.", "Sanitation", "Garbage collection", :web_portal ],
    [ "No water supply in %s colony", "There has been no municipal water supply for two days. Children and elderly residents are affected.", "Water Supply", "Water supply", :web_portal ],
    [ "Streetlight broken near %s chowk", "The streetlight has been dark for a week. The stretch is unsafe at night.", "Sanitation", "Street lighting", :email ],
    [ "Debit card blocked after wrong PIN at %s ATM", "My card was blocked after three wrong PIN attempts. I need it urgently for medical payments.", "Banking Services", "Card services", :api ],
    [ "Card retained by ATM at %s", "The ATM swallowed my debit card during a withdrawal. No receipt was printed.", "Banking Services", "Card services", :email ],
    [ "Wrong charges on savings account — %s", "A service charge of Rs 590 was debited twice this quarter. Requesting reversal.", "Banking Services", "Account services", :web_portal ],
    [ "Water tanker request for %s", "Our locality qualifies for a tanker after the pipeline burst. Please dispatch one.", "Water Supply", "Water supply", :phone ],
    [ "Pension arrears pending since %s", "Arrears for three months are pending after revision. Multiple visits to the office have not helped.", "Pensions", "Pension delay", :walk_in ],
    [ "Open manhole near %s school", "A manhole cover is missing on the school route. This is dangerous for children.", "Sanitation", "Other", :web_portal ]
  ]
  places = [ "Karol Bagh", "Rajouri Garden", "Mayur Vihar", "Saket", "Dwarka", "Pitampura",
             "Lajpat Nagar", "Janakpuri", "Rohini", "Vasant Kunj" ]
  agent_pool = [ users["Priya Nair"], users["Rohan Gupta"], users["Fatima Khan"], users["Deepak Yadav"] ]
  status_plan = (
    [ :new ] * 8 + [ :triaged ] * 9 + [ :in_progress ] * 14 + [ :waiting_on_citizen ] * 7 +
    [ :resolved ] * 12 + [ :closed ] * 8 + [ :reopened ] * 2
  )

  status_plan.each_with_index do |target_status, index|
    subject_template, body, queue_name, category_name, channel = templates[index % templates.size]
    place = places[index % places.size]
    contact = citizens[rng.rand(citizens.size)]
    banking = queue_name == "Banking Services"
    created_at = (2 + rng.rand(55)).days.ago + rng.rand(8).hours

    kase = Case.create!(
      subject: format(subject_template, place) + (index >= templates.size ? " (#{index + 1})" : ""),
      contact: contact,
      channel: channel,
      priority: [ :low, :normal, :normal, :normal, :high, :urgent ][rng.rand(6)],
      queue: queues[queue_name],
      category: categories[category_name],
      sla_policy: banking ? banking_policy = SlaPolicy.find_by!(name: "Priority banking") : standard
    )
    kase.messages.create!(kind: :public_reply, direction: :inbound, author: contact, body: body)

    agent = agent_pool[rng.rand(agent_pool.size)]

    path = case target_status
    when :new then []
    when :triaged then [ :triaged ]
    when :in_progress then [ :triaged, :in_progress ]
    when :waiting_on_citizen then [ :triaged, :in_progress, :waiting_on_citizen ]
    when :resolved then [ :triaged, :in_progress, :resolved ]
    when :closed then [ :triaged, :in_progress, :resolved, :closed ]
    when :reopened then [ :triaged, :in_progress, :resolved, :reopened ]
    end

    Current.set(actor: users["Sunita Rao"]) do
      kase.update!(assignee: agent) unless target_status == :new
      path.each { |s| kase.transition_to!(s) }
    end

    if path.include?(:in_progress)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "Dear #{contact.name}, your case #{kase.tracking_id} is being processed. We will update you here.")
        if rng.rand < 0.4
          kase.messages.create!(kind: :internal_note, direction: :outbound, author: agent,
            body: "Verified details with the field team; awaiting confirmation.")
        end
      end
    end
    if path.include?(:waiting_on_citizen)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "We need one more detail to proceed — please share your registered address by replying here.")
      end
    end
    if path.include?(:resolved)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "The issue has been addressed. Reply within 7 days if it persists and the case will be reopened.")
      end
    end
    if target_status == :reopened
      kase.messages.create!(kind: :public_reply, direction: :inbound, author: contact,
        body: "The problem has come back. Please look into it again.")
    end

    # Backdate the record so lists, SLA timers, and reports look lived-in.
    age_offsets = { created_at: created_at, updated_at: created_at + rng.rand(72).hours }
    age_offsets[:resolved_at] = created_at + (12 + rng.rand(60)).hours if kase.resolved_at
    age_offsets[:closed_at] = created_at + (80 + rng.rand(80)).hours if kase.closed_at
    age_offsets[:first_responded_at] = created_at + (1 + rng.rand(10)).hours if kase.first_responded_at
    kase.update_columns(age_offsets)

    target = kase.sla_policy&.target_for(kase.priority)
    if target
      kase.update_columns(
        first_response_due_at: created_at + target.first_response_minutes.minutes,
        resolution_due_at: created_at + target.resolution_minutes.minutes
      )
    end
  end

  SlaBreachSweepJob.perform_now

  # One AI-handled showcase case (FakeLlmClient).
  showcase_contact = citizens[1]
  showcase = Case.create!(
    subject: "Water supply disrupted after pipeline work",
    contact: showcase_contact,
    channel: :web_portal,
    queue: queues["General"],
    sla_policy: standard
  )
  showcase.messages.create!(kind: :public_reply, direction: :inbound, author: showcase_contact,
    body: "There has been no water in our lane since the pipeline work on Sunday. When will supply resume?")
  CaseAgentJob.perform_now(showcase)

  Setting.set("demo_seeded", true)
end

puts "Demo data ready:"
puts "  staff login:  arjun@docket.local / #{ENV.fetch("DOCKET_DEMO_PASSWORD", "docket-demo")} (admin)"
puts "  also: sunita@ (supervisor), priya@ / rohan@ / fatima@ / deepak@ (agents), meena@ (read-only)"
puts "  cases: #{Case.count}, contacts: #{Contact.count}, audit entries: #{AuditEntry.count}"
