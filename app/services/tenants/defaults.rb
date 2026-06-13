module Tenants
  # The day-one floor every tenant needs to take tickets and deals: a default
  # sales pipeline, a ticket queue, and an SLA policy (with the queue/SLA wired
  # as the tenant's Settings defaults). Idempotent (.none? guards — scoped to the
  # caller's current tenant), so re-running is a no-op and it never overrides an
  # operator's own setup. Runs INSIDE the caller's tenant scope: db/seeds.rb uses
  # it for the primary tenant, Tenants::Provisioner for each new shared tenant.
  module Defaults
    module_function

    def seed!
      seed_pipeline!
      seed_queue!
      seed_sla!
    end

    def seed_pipeline!
      return unless defined?(Pipeline) && Pipeline.none?

      pipeline = Pipeline.new(name: "Sales", slug: "sales", position: 0)
      pipeline.pipeline_stages.build([
        { name: "New", position: 0, probability: 10 },
        { name: "Contacted", position: 1, probability: 25 },
        { name: "Qualified", position: 2, probability: 50 },
        { name: "Proposal", position: 3, probability: 75 },
        { name: "Won", position: 4, probability: 100, is_won: true },
        { name: "Lost", position: 5, probability: 0, is_lost: true }
      ])
      pipeline.save!
      puts "  default pipeline: #{pipeline.name} (#{pipeline.pipeline_stages.size} stages)"
    end

    def seed_queue!
      return unless defined?(CaseQueue) && CaseQueue.none?

      queue = CaseQueue.create!(name: "General", description: "Default queue for incoming requests.")
      Setting.set("default_queue_id", queue.id)
      puts "  default queue: #{queue.name}"
    end

    def seed_sla!
      return unless defined?(SlaPolicy) && SlaPolicy.none?

      sla = SlaPolicy.create!(name: "Standard", description: "Default first-response and resolution targets.")
      # [priority, first_response_minutes, resolution_minutes] — 8h/7d down to 30m/8h.
      [ [ :low, 480, 10080 ], [ :normal, 240, 4320 ], [ :high, 60, 1440 ], [ :urgent, 30, 480 ] ].each do |priority, fr, res|
        sla.sla_targets.create!(priority: priority, first_response_minutes: fr, resolution_minutes: res)
      end
      Setting.set("default_sla_policy_id", sla.id)
      puts "  default SLA policy: #{sla.name} (#{sla.sla_targets.size} targets)"
    end
  end
end
