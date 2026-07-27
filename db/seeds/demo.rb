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
    [ "Arjun Mehta", "arjun@docket.local", :super_admin ],
    [ "Sunita Rao", "sunita@docket.local", :client_admin ],
    [ "Vikram Joshi", "vikram@docket.local", :client_admin ],
    [ "Priya Nair", "priya@docket.local", :customer_service ],
    [ "Rohan Gupta", "rohan@docket.local", :customer_service ],
    [ "Fatima Khan", "fatima@docket.local", :customer_service ],
    [ "Deepak Yadav", "deepak@docket.local", :customer_service ],
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
    [ :new ] * 5 + [ :triaged ] * 6 + [ :in_progress ] * 9 + [ :waiting_on_customer ] * 4 +
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
      waiting_on_customer: [ :triaged, :in_progress, :waiting_on_customer ],
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
    if path.include?(:waiting_on_customer)
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

  # --- Sales pipeline deals (populate the Sales report: open funnel, weighted
  # forecast, won/lost + win rate, loss reasons, by-owner, velocity). Values in
  # ₹; the demo runs 7 open / 5 won / 4 lost. Created dates are aged into the
  # last ~30 days so the report's default window is populated.
  #
  # Won/lost deliberately keep closed_at ≈ now: the stage-dwell timeline is
  # reconstructed from the append-only, hash-chained audit log, whose entries
  # are stamped at seed time — a *past* closed_at would read as negative dwell.
  # avg-days-to-win measures created_at → closed_at, so ageing created_at alone
  # gives a realistic headline without corrupting the audit-mined dwell.
  # Stages are resolved by their won/lost flags and position (not by name), so
  # this works against whatever the deployment's default pipeline looks like.
  pipe = Pipeline.default
  open_stages = pipe&.pipeline_stages&.select { |s| s.implied_status == :open }&.sort_by(&:position) || []
  won_stage   = pipe&.pipeline_stages&.find(&:is_won?)
  lost_stage  = pipe&.pipeline_stages&.find(&:is_lost?)
  if Deal.none? && open_stages.any?
    reps = [ users["Priya Nair"], users["Sunita Rao"], users["Rohan Gupta"],
             users["Fatima Khan"], users["Arjun Mehta"] ].compact
    deal_nouns = %w[Expansion Renewal Onboarding Upgrade Add-on Rollout Pilot
                    Contract Seats Integration Platform Migration]
    open_at = ->(i) { open_stages[[ i, open_stages.size - 1 ].min] } # clamp to funnel depth
    # [target, value₹, created_days_ago, lost_reason|nil, expected_close_in_days|nil]
    #   target: an integer indexes the open funnel (0 = first); :won / :lost hit the terminal stages.
    deal_plan = [
      [ 3, 450_000, 14, nil, 12 ],
      [ 2, 880_000, 12, nil, 25 ],
      [ 3, 620_000,  6, nil,  8 ],
      [ 2, 280_000, 10, nil, 20 ],
      [ 1, 210_000,  3, nil, 18 ],
      [ 1, 150_000,  8, nil, 30 ],
      [ 0,  95_000,  4, nil, 45 ],
      [ :won,  540_000, 28, nil, nil ],
      [ :won,  410_000, 22, nil, nil ],
      [ :won,  320_000, 26, nil, nil ],
      [ :won,  275_000, 29, nil, nil ],
      [ :won,  120_000, 20, nil, nil ],
      [ :lost, 700_000, 27, :price,      nil ],
      [ :lost, 480_000, 24, :competitor, nil ],
      [ :lost, 360_000, 19, :no_budget,  nil ],
      [ :lost, 230_000, 15, :timing,     nil ]
    ]
    deal_plan.each_with_index do |(target, value, created_days_ago, lost_reason, close_in), i|
      stage = case target
      when :won  then won_stage
      when :lost then lost_stage
      else open_at.call(target)
      end
      next if stage.nil? # pipeline lacks a won/lost stage — skip that deal

      contact = contacts[i % contacts.size]
      org = contact.organisation || orgs[i % orgs.size]
      deal = Deal.new(
        name: "#{org.name} — #{deal_nouns[i % deal_nouns.size]}",
        pipeline: pipe, pipeline_stage: stage,
        owner: reps[i % reps.size], contact: contact, organisation: org,
        value: value, expected_close_on: close_in && (Date.current + close_in)
      )
      deal.save!
      deal.update_columns(created_at: created_days_ago.days.ago)
      unless stage.implied_status == :open
        # Re-stamp closed_at strictly after the create-audit entry (keeps the
        # audit-mined stage dwell non-negative); record the loss reason.
        deal.update_columns(closed_at: Time.current)
        deal.update_columns(lost_reason: Deal.lost_reasons.fetch(lost_reason)) if lost_reason
      end
    end

    # One converted lead so the lead-conversion metric reads a real rate.
    if (converted = Lead.where(status: :qualified).first)
      converted.update_columns(status: Lead.statuses.fetch("converted"), converted_at: Time.current)
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

  # --- Work module: a project, a board with work in every column, a closed
  # sprint so velocity has history, and an active one. Plus ONE case escalated
  # to engineering, so the cross-module seam is visible without anyone having
  # to construct it. Skipped when the tenant doesn't hold the module.
  if Features.enabled?("work") && (spec = scenario[:project])
    project = Project.create!(key: spec[:key], name: spec[:name], lead: users["Arjun Mehta"])
    states = project.workflow_states.ordered.to_a
    states[2].update!(wip_limit: 3) # "In progress" — demo data deliberately sits at the limit

    closed_sprint = project.sprints.create!(
      name: "Sprint 11", goal: "Hardening", status: :closed,
      starts_on: Date.current - 28, ends_on: Date.current - 14
    )
    active_sprint = project.sprints.create!(
      name: "Sprint 12", goal: spec[:goal], status: :active,
      starts_on: Date.current - 4, ends_on: Date.current + 10
    )

    workers = agent_pool.compact
    # Column spread: 2 backlog, 1 todo, 3 in progress (at the WIP limit), 1 review, 1 done.
    placement = [ 0, 0, 1, 2, 2, 2, 3, 4 ]

    spec[:items].each_with_index do |(title, kind, priority, estimate), i|
      state = states[placement[i]] || project.default_state
      item = project.work_items.create!(
        title: title, kind: kind, priority: priority, estimate: estimate,
        workflow_state: state, sprint: active_sprint,
        reporter: users["Arjun Mehta"], assignee: workers[i % workers.size],
        due_on: (Date.current + (i * 3) - 4)
      )
      item.work_comments.create!(body: "Picked this up — will update after the next deploy.",
                                 author: item.assignee) if i.even? && item.assignee
      item.work_watches.create!(user: users["Sunita Rao"]) if i < 3
    end

    # Closed-sprint history so the velocity report is not an empty table.
    # Backdated deliberately: cycle time is measured created_at -> closed_at, so
    # items created "now" would report a median of 0 days and make the report
    # look broken on a fresh demo.
    [ [ 3, 26, 16 ], [ 5, 25, 13 ], [ 2, 22, 15 ] ].each_with_index do |(estimate, opened, closed), i|
      item = project.work_items.create!(
        title: "Completed in Sprint 11 (#{i + 1})", kind: :task, priority: :normal,
        estimate: estimate, workflow_state: states.last, sprint: closed_sprint,
        reporter: users["Arjun Mehta"], assignee: workers[i % workers.size]
      )
      item.update_columns(created_at: Time.current - opened.days,
                          closed_at: Time.current - closed.days)
    end

    # The seam: one real case handed to engineering.
    escalated = Case.status_in_progress.first || Case.first
    if escalated
      handoff = Work::Escalation.call(kase: escalated, project: project, actor: users["Arjun Mehta"],
                                      title: "Engineering follow-up: #{escalated.subject}", kind: :bug)
      handoff.work_item.update!(assignee: workers.first, sprint: active_sprint)
    end
  end

  Setting.set("demo_seeded", true)
end

puts "Demo data ready (brand: #{scenario[:brand]}):"
puts "  staff login: arjun@docket.local / #{ENV.fetch('DOCKET_DEMO_PASSWORD', 'docket-demo')} (admin)"
puts "  also: sunita@ (supervisor), priya@/rohan@/fatima@/deepak@ (agents), meena@ (read-only)"
puts "  cases: #{Case.count}, contacts: #{Contact.count}, leads: #{Lead.count}, " \
     "deals: #{Deal.count} (#{Deal.status_open.count} open/#{Deal.status_won.count} won/#{Deal.status_lost.count} lost), " \
     "connectors: #{Connector.count}, pending agent actions: #{ConnectorInvocation.status_proposed.count}"
puts "  work: #{Project.count} project, #{WorkItem.count} items, #{Sprint.count} sprints, " \
     "#{WorkLink.count} case-to-work link" if Project.any?
