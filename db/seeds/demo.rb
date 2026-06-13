# Sample-data loader. Seeds a believable demo dataset for the scenario named by
# DOCKET_SEED_SCENARIO (saas | retail | gov — default saas), covering every
# surface so demos / guides / walkthroughs never hit an empty state: staff,
# customers, support cases across every status + channel, a sales pipeline, a
# knowledge base, and the AI effector layer (a connector, a designated agent,
# items awaiting approval). Idempotent via the demo_seeded marker. All
# fictional. Switch scenarios on a fresh database.
require_relative "demo_scenarios"
return if Setting.get("demo_seeded")

scenario = DemoScenarios.fetch(ENV.fetch("DOCKET_SEED_SCENARIO", "saas"))
rng = Random.new(42)
puts "Seeding demo data (scenario: #{ENV.fetch('DOCKET_SEED_SCENARIO', 'saas')})…"

# Demo data owns a tenant; seed it into the primary (resolves to the existing
# test tenant when invoked from the suite). Leaves an already-set tenant intact.
ActsAsTenant.current_tenant ||= Tenant.find_or_create_by!(slug: Tenant::PRIMARY_SLUG) { |t| t.name = "Docket" }

Current.set(actor: nil) do
  Setting.set("llm_provider", "fake")
  Setting.set("ai_draft_enabled", true)
  Setting.set("brand_name", scenario[:brand])

  # --- Organisations (indexable for contact references) ---
  orgs = scenario[:orgs].map do |name, kind, ref|
    Organisation.find_or_create_by!(name: name) do |o|
      o.kind = kind
      o.external_ref = ref
    end
  end

  # --- Queues ---
  queues = {}
  scenario[:queues].each do |name, description|
    queues[name] = CaseQueue.find_or_create_by!(name: name) { |q| q.description = description }
  end
  queue_names = scenario[:queues].map(&:first)

  # --- Staff (names are scenario-neutral; logins stay stable) ---
  password = ENV.fetch("DOCKET_DEMO_PASSWORD", "docket-demo")
  staff_plan = [
    [ "Arjun Mehta", "arjun@docket.local", :admin ],
    [ "Sunita Rao", "sunita@docket.local", :supervisor ],
    [ "Vikram Joshi", "vikram@docket.local", :supervisor ],
    [ "Priya Nair", "priya@docket.local", :agent ],
    [ "Rohan Gupta", "rohan@docket.local", :agent ],
    [ "Fatima Khan", "fatima@docket.local", :agent ],
    [ "Deepak Yadav", "deepak@docket.local", :agent ],
    [ "Meena Iyer", "meena@docket.local", :readonly ]
  ]
  users = {}
  staff_plan.each_with_index do |(name, email, role), i|
    user = User.find_or_create_by!(email_address: email) do |u|
      u.name = name
      u.role = role
      u.password = password
    end
    unless role == :readonly
      [ queue_names[i % queue_names.size], queue_names[(i + 1) % queue_names.size] ].uniq.each do |qn|
        QueueMembership.find_or_create_by!(user: user, queue: queues[qn])
      end
    end
    users[name] = user
  end
  agent_pool = [ users["Priya Nair"], users["Rohan Gupta"], users["Fatima Khan"], users["Deepak Yadav"] ]

  # --- Categories ---
  categories = {}
  scenario[:categories].each { |name| categories[name] = Category.find_or_create_by!(name: name) }

  # --- SLA policies (standard + priority) ---
  standard = SlaPolicy.find_or_create_by!(name: scenario[:sla][:standard]) { |p| p.description = "Default response/resolution targets" }
  if standard.sla_targets.empty?
    [ [ :low, 480, 10080 ], [ :normal, 240, 4320 ], [ :high, 60, 1440 ], [ :urgent, 30, 480 ] ].each do |priority, fr, res|
      standard.sla_targets.create!(priority: priority, first_response_minutes: fr, resolution_minutes: res)
    end
  end
  priority = SlaPolicy.find_or_create_by!(name: scenario[:sla][:priority]) { |p| p.description = "Tighter targets for priority work" }
  if priority.sla_targets.empty?
    [ [ :low, 240, 4320 ], [ :normal, 120, 1440 ], [ :high, 30, 480 ], [ :urgent, 15, 240 ] ].each do |pr, fr, res|
      priority.sla_targets.create!(priority: pr, first_response_minutes: fr, resolution_minutes: res)
    end
  end
  Setting.set("default_sla_policy_id", standard.id)
  Setting.set("default_queue_id", queues[queue_names.last].id)

  # --- Macros (generic) ---
  [ [ "Acknowledgement",
      "Hi {{contact_name}},\n\nYour case {{tracking_id}} has been received and is with our {{queue_name}} team. We'll update you here.\n\nThanks,\n{{agent_name}}" ],
    [ "More information needed",
      "Hi {{contact_name}},\n\nTo proceed with {{tracking_id}} we need a few more details. Please reply with the requested information.\n\nThanks,\n{{agent_name}}" ],
    [ "Resolution confirmation",
      "Hi {{contact_name}},\n\n{{tracking_id}} has been resolved. If it recurs, just reply and the case will reopen.\n\nThanks,\n{{agent_name}}" ] ].each do |name, body|
    Macro.find_or_create_by!(name: name) { |m| m.body = body }
  end

  # --- Knowledge base (AI grounding) ---
  scenario[:kb].each { |title, body| ReferenceDoc.find_or_create_by!(title: title) { |d| d.body = body } }

  # --- Contacts ---
  contacts = scenario[:contacts].map do |name, email, phone, ext, org_index, lang|
    Contact.find_or_create_by!(name: name) do |c|
      c.email = email
      c.phone = phone
      c.external_id = ext
      c.organisation = org_index && orgs[org_index]
      c.preferred_language = lang
    end
  end

  # --- Cases across every status + channel ---
  templates = scenario[:templates]
  places = scenario[:places]
  status_plan = (
    [ :new ] * 5 + [ :triaged ] * 6 + [ :in_progress ] * 9 + [ :waiting_on_citizen ] * 4 +
    [ :resolved ] * 8 + [ :closed ] * 5 + [ :reopened ] * 2
  )

  status_plan.each_with_index do |target_status, index|
    subject_template, body, queue_name, category_name, channel = templates[index % templates.size]
    place = places[index % places.size]
    contact = contacts[rng.rand(contacts.size)]
    case_priority = [ :low, :normal, :normal, :normal, :high, :urgent ][rng.rand(6)]
    created_at = (2 + rng.rand(55)).days.ago + rng.rand(8).hours

    kase = Case.create!(
      subject: format(subject_template, place) + (index >= templates.size ? " (#{index + 1})" : ""),
      contact: contact, channel: channel, priority: case_priority,
      queue: queues[queue_name], category: categories[category_name],
      sla_policy: [ :high, :urgent ].include?(case_priority) ? priority : standard
    )
    kase.messages.create!(kind: :public_reply, direction: :inbound, author: contact, body: body)

    agent = agent_pool[rng.rand(agent_pool.size)]
    path = {
      new: [], triaged: [ :triaged ], in_progress: [ :triaged, :in_progress ],
      waiting_on_citizen: [ :triaged, :in_progress, :waiting_on_citizen ],
      resolved: [ :triaged, :in_progress, :resolved ],
      closed: [ :triaged, :in_progress, :resolved, :closed ],
      reopened: [ :triaged, :in_progress, :resolved, :reopened ]
    }.fetch(target_status)

    Current.set(actor: users["Sunita Rao"]) do
      kase.update!(assignee: agent) unless target_status == :new
      path.each { |s| kase.transition_to!(s) }
    end

    if path.include?(:in_progress)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "Hi #{contact.name}, your case #{kase.tracking_id} is being looked into. We'll update you here.")
        if rng.rand < 0.4
          kase.messages.create!(kind: :internal_note, direction: :outbound, author: agent,
            body: "Reproduced / verified with the team; awaiting confirmation.")
        end
      end
    end
    if path.include?(:waiting_on_citizen)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "We need one more detail to proceed — please reply here with the requested information.")
      end
    end
    if path.include?(:resolved)
      Current.set(actor: agent) do
        kase.messages.create!(kind: :public_reply, direction: :outbound, author: agent,
          body: "This has been addressed. Reply within 7 days if it persists and the case will reopen.")
      end
    end
    if target_status == :reopened
      kase.messages.create!(kind: :public_reply, direction: :inbound, author: contact,
        body: "The problem has come back. Please look into it again.")
    end

    age = { created_at: created_at, updated_at: created_at + rng.rand(72).hours }
    age[:resolved_at] = created_at + (12 + rng.rand(60)).hours if kase.resolved_at
    age[:closed_at] = created_at + (80 + rng.rand(80)).hours if kase.closed_at
    age[:first_responded_at] = created_at + (1 + rng.rand(10)).hours if kase.first_responded_at
    kase.update_columns(age)

    if (target = kase.sla_policy&.target_for(kase.priority))
      kase.update_columns(
        first_response_due_at: created_at + target.first_response_minutes.minutes,
        resolution_due_at: created_at + target.resolution_minutes.minutes
      )
    end
  end

  SlaBreachSweepJob.perform_now

  # --- One AI-handled showcase case (FakeClient) ---
  sc_subject, sc_body = scenario[:showcase]
  showcase_contact = contacts[1]
  showcase = Case.create!(subject: sc_subject, contact: showcase_contact, channel: :web_portal,
                          queue: queues[queue_names.last], sla_policy: standard)
  showcase.messages.create!(kind: :public_reply, direction: :inbound, author: showcase_contact, body: sc_body)
  CaseAgentJob.perform_now(showcase)

  # --- Sales funnel (leads + an outreach sequence) ---
  sales_owner = users["Priya Nair"]
  scenario[:leads].each do |attrs|
    Lead.find_or_create_by!(email: attrs[:email]) { |l| l.assign_attributes(attrs.merge(owner: sales_owner)) }
  end
  unless Sequence.exists?(name: "New-lead welcome")
    welcome = Sequence.new(name: "New-lead welcome", active: true)
    welcome.sequence_steps.build(position: 0, delay_days: 0, subject: "Thanks for reaching out, {{contact_name}}",
      body: "Hi {{contact_name}},\n\nThanks for your interest. A member of our team will be in touch shortly.")
    welcome.sequence_steps.build(position: 1, delay_days: 3, subject: "Following up",
      body: "Hi {{contact_name}},\n\nJust checking in to see if you had any questions about {{company_name}}.")
    welcome.save!
    if (first_lead = Lead.where(status: %w[new working]).first)
      welcome.enroll!(first_lead)
    end
  end

  # --- AI effector layer (connector + designated agent + approval queue) ---
  effector_agent = ServiceAccount.find_or_create_by!(name: "Support effector agent") do |sa|
    sa.scopes = %w[contacts:read cases:read connectors:invoke]
    sa.active = true
    sa.action_budget = 50
    sa.action_budget_window_minutes = 60
  end
  Setting.set("effector_agent_id", effector_agent.id)

  shared = SharedCredential.find_or_create_by!(name: "support_api") { |s| s.label = "Support API key" }
  if shared.secret("api_key").blank?
    shared.secrets_hash = { "api_key" => "demo-shared-key" }
    shared.save!
  end

  connector = Connector.find_or_create_by!(name: "#{scenario[:brand]} records API") do |c|
    c.provider = "http_json"
    c.target = "contacts"
    c.field_mapping = { "external_id" => "id", "email" => "email", "name" => "name" }
    c.config = { "endpoint_url" => "https://api.example.com/contacts", "action_url" => "https://api.example.com/actions" }
    c.enabled_actions = %w[post_json]
    c.shared_credential = shared
    c.status = :active
  end

  if connector.invocations.empty?
    recent = Case.order(:id).last(2)
    Current.set(actor: effector_agent, on_behalf_of: "case:#{recent.first&.id}") do
      connector.invocations.create!(action: "post_json", decision_class: "confirm", effect: "write",
        status: :proposed, requested_by: effector_agent, on_behalf_of: "case:#{recent.first&.id}",
        reasoning: "Drafted a status update for the customer; awaiting approval.",
        args: { "body" => { "template" => "status_update" } })
    end
    Current.set(actor: effector_agent, on_behalf_of: "case:#{recent.last&.id}") do
      connector.invocations.create!(action: "post_json", decision_class: "of_record", effect: "irreversible",
        status: :proposed, requested_by: effector_agent, on_behalf_of: "case:#{recent.last&.id}",
        reasoning: "Proposed a refund; needs a human-of-record decision with a reasoned order.",
        args: { "body" => { "refund" => true } })
    end
  end

  Setting.set("demo_seeded", true)
end

puts "Demo data ready (brand: #{scenario[:brand]}):"
puts "  staff login: arjun@docket.local / #{ENV.fetch('DOCKET_DEMO_PASSWORD', 'docket-demo')} (admin)"
puts "  also: sunita@ (supervisor), priya@/rohan@/fatima@/deepak@ (agents), meena@ (read-only)"
puts "  cases: #{Case.count}, contacts: #{Contact.count}, leads: #{Lead.count}, " \
     "connectors: #{Connector.count}, pending agent actions: #{ConnectorInvocation.status_proposed.count}"
