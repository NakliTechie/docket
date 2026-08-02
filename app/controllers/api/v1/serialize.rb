module Api
  module V1
    # Plain-hash serializers — one place, no view framework.
    module Serialize
      module_function

      def kase(c, include_messages: false)
        base = {
          id: c.id,
          tracking_id: c.tracking_id,
          subject: c.subject,
          description: c.description,
          status: c.status,
          priority: c.priority,
          channel: c.channel,
          queue_id: c.queue_id,
          queue_slug: c.queue&.slug,
          category_id: c.category_id,
          category: c.category&.name,
          assignee_id: c.assignee_id,
          owner_id: c.owner_id,
          contact_id: c.contact_id,
          sla_policy_id: c.sla_policy_id,
          first_response_due_at: c.first_response_due_at,
          resolution_due_at: c.resolution_due_at,
          first_responded_at: c.first_responded_at,
          resolved_at: c.resolved_at,
          closed_at: c.closed_at,
          first_response_breached: c.first_response_breached,
          resolution_breached: c.resolution_breached,
          custom_fields: c.custom_fields,
          merged_into_id: c.merged_into_id, merged_at: c.merged_at,
          merged_case_ids: c.merged_cases.ids,
          reopen_count: c.reopen_count,
          allowed_transitions: Case::TRANSITIONS.fetch(c.status, []),
          created_at: c.created_at,
          updated_at: c.updated_at
        }
        base[:messages] = c.messages.order(:created_at).map { |m| message(m) } if include_messages
        base
      end

      def message(m)
        {
          id: m.id,
          case_id: m.case_id,
          kind: m.kind,
          direction: m.direction,
          author_type: m.author_type,
          author_id: m.author_id,
          subject: m.subject,
          body: m.body,
          metadata: safe_metadata(m.metadata),
          attachments: m.files.map { |f|
            { filename: f.filename.to_s, content_type: f.content_type, byte_size: f.byte_size,
              url: Rails.application.routes.url_helpers.rails_blob_path(f, disposition: "attachment", only_path: true) }
          },
          created_at: m.created_at
        }
      end

      # The AI turn log stores the full prompt + raw model response in
      # message metadata for the internal audit trail; don't leak those
      # verbose internals over the API. Flags/confidence/rationale stay.
      def safe_metadata(metadata)
        return metadata unless metadata.is_a?(Hash)
        metadata.except("prompt", "response")
      end

      def contact(c)
        {
          id: c.id, name: c.name, email: c.email, phone: c.phone,
          job_title: c.job_title, whatsapp_handle: c.whatsapp_handle,
          telegram_handle: c.telegram_handle,
          external_id: c.external_id, organisation_id: c.organisation_id, owner_id: c.owner_id,
          preferred_language: c.preferred_language, notes: c.notes,
          sms_consent: c.sms_consent, email_consent: c.email_consent,
          email_unsubscribed_at: c.email_unsubscribed_at,
          labels: c.labels, custom_fields: c.custom_fields,
          created_at: c.created_at, updated_at: c.updated_at
        }
      end

      def organisation(o)
        { id: o.id, name: o.name, kind: o.kind, external_ref: o.external_ref, owner_id: o.owner_id,
          notes: o.notes, created_at: o.created_at, updated_at: o.updated_at }
      end

      def project(p)
        {
          id: p.id, key: p.key, name: p.name, description: p.description,
          lead_id: p.lead_id, archived: p.archived, visibility: p.visibility,
          onboarding_deal_id: p.onboarding_deal_id, project_template_id: p.project_template_id,
          member_ids: p.project_memberships.map(&:user_id),
          assignment_rules: p.work_assignment_rules.map { |rule|
            { id: rule.id, work_kind: rule.work_kind, assignee_id: rule.assignee_id }
          },
          created_at: p.created_at, updated_at: p.updated_at
        }
      end

      def project_template(template)
        {
          id: template.id, name: template.name, key_prefix: template.key_prefix,
          description: template.description, active: template.active,
          items: template.project_template_items.map { |item|
            { id: item.id, title: item.title, description: item.description,
              kind: item.kind, priority: item.priority, estimate: item.estimate&.to_f,
              due_offset_days: item.due_offset_days, position: item.position }
          },
          created_at: template.created_at, updated_at: template.updated_at
        }
      end

      def work_item(i)
        {
          id: i.id, reference: i.reference, project_id: i.project_id,
          number: i.number, title: i.title, description: i.description,
          kind: i.kind, priority: i.priority,
          workflow_state_id: i.workflow_state_id, workflow_state: i.workflow_state&.name,
          state_category: i.workflow_state&.category,
          assignee_id: i.assignee_id, reporter_id: i.reporter_id,
          parent_id: i.parent_id, sprint_id: i.sprint_id,
          labels: i.labels, estimate: i.estimate&.to_f, due_on: i.due_on,
          custom_fields: i.custom_fields,
          relations: relation_summaries(i),
          closed_at: i.closed_at, created_at: i.created_at, updated_at: i.updated_at
        }
      end

      def work_item_relation(relation)
        {
          id: relation.id, relation_type: relation.relation_type,
          source_id: relation.source_id, source_reference: relation.source.reference,
          target_id: relation.target_id, target_reference: relation.target.reference,
          created_by_id: relation.created_by_id, created_at: relation.created_at
        }
      end

      def relation_summaries(item)
        (item.outgoing_relations.includes(:source, :target).to_a +
          item.incoming_relations.includes(:source, :target).to_a).uniq.map do |relation|
          work_item_relation(relation)
        end
      end

      def sprint(s)
        {
          id: s.id, project_id: s.project_id, name: s.name, goal: s.goal,
          status: s.status, starts_on: s.starts_on, ends_on: s.ends_on,
          created_at: s.created_at, updated_at: s.updated_at
        }
      end

      def work_comment(c)
        {
          id: c.id, work_item_id: c.work_item_id,
          author_type: c.author_type, author_id: c.author_id,
          body: c.body, created_at: c.created_at, updated_at: c.updated_at
        }
      end

      def lead(l)
        {
          id: l.id, name: l.name, email: l.email, phone: l.phone,
          job_title: l.job_title, whatsapp_handle: l.whatsapp_handle,
          telegram_handle: l.telegram_handle,
          company_name: l.company_name, source: l.source, status: l.status,
          owner_id: l.owner_id, contact_id: l.contact_id, converted_deal_id: l.converted_deal_id,
          value_estimate_cents: l.value_estimate_cents, notes: l.notes,
          sms_consent: l.sms_consent, email_consent: l.email_consent,
          email_unsubscribed_at: l.email_unsubscribed_at,
          consent_captured_at: l.consent_captured_at, consent_source: l.consent_source,
          first_touch_campaign_id: l.first_touch_campaign_id, first_touch_at: l.first_touch_at,
          first_touch_utm_source: l.first_touch_utm_source,
          first_touch_utm_medium: l.first_touch_utm_medium,
          first_touch_utm_campaign: l.first_touch_utm_campaign,
          first_touch_utm_term: l.first_touch_utm_term,
          first_touch_utm_content: l.first_touch_utm_content,
          first_touch_landing_page: l.first_touch_landing_page,
          first_touch_referrer: l.first_touch_referrer,
          provenance: l.provenance, merged_into_id: l.merged_into_id, merged_at: l.merged_at,
          custom_fields: l.custom_fields,
          merged_lead_ids: l.merged_leads.ids,
          converted_at: l.converted_at, created_at: l.created_at, updated_at: l.updated_at
        }
      end

      def lead_capture_form(form)
        { id: form.id, name: form.name, slug: form.slug, field_mapping: form.field_mapping,
          consent_disclosure: form.consent_disclosure, active: form.active,
          is_default: form.is_default, campaign_id: form.campaign_id,
          created_at: form.created_at, updated_at: form.updated_at }
      end

      def deal(d)
        {
          id: d.id, name: d.name, pipeline_id: d.pipeline_id, pipeline_stage_id: d.pipeline_stage_id,
          status: d.status, value_cents: d.value_cents, currency: d.currency,
          owner_id: d.owner_id, contact_id: d.contact_id, organisation_id: d.organisation_id,
          lead_id: d.lead_id, expected_close_on: d.expected_close_on, closed_at: d.closed_at,
          lost_reason: d.lost_reason, onboarding_project_id: d.onboarding_project&.id,
          notes: d.notes, next_step: d.next_step, next_step_at: d.next_step_at,
          first_touch_campaign_id: d.first_touch_campaign_id, first_touch_at: d.first_touch_at,
          first_touch_utm_source: d.first_touch_utm_source,
          first_touch_utm_medium: d.first_touch_utm_medium,
          first_touch_utm_campaign: d.first_touch_utm_campaign,
          first_touch_utm_term: d.first_touch_utm_term,
          first_touch_utm_content: d.first_touch_utm_content,
          first_touch_landing_page: d.first_touch_landing_page,
          first_touch_referrer: d.first_touch_referrer,
          custom_fields: d.custom_fields,
          line_items_total_cents: d.line_items_total_cents,
          line_items: d.deal_line_items.map { |item| deal_line_item(item) },
          competitors: d.deal_competitors.map { |link| deal_competitor(link) },
          created_at: d.created_at, updated_at: d.updated_at
        }
      end

      def crm_message(message)
        {
          id: message.id, subject_type: message.subject_type, subject_id: message.subject_id,
          channel: message.channel, direction: message.direction,
          author_type: message.author_type, author_id: message.author_id,
          sender_email: message.sender_email, recipient_email: message.recipient_email,
          subject_line: message.subject_line, body: message.body,
          delivery_status: message.delivery_status, occurred_at: message.occurred_at,
          created_at: message.created_at, updated_at: message.updated_at
        }
      end

      def crm_conversation_entry(entry)
        {
          record_type: entry.record.class.name, record_id: entry.record.id,
          context: entry.context, channel: entry.channel, direction: entry.direction,
          author: entry.author, subject_line: entry.subject_line,
          body: entry.body, occurred_at: entry.occurred_at
        }
      end

      def activity(a)
        { id: a.id, kind: a.kind, title: a.title, body: a.body,
          subject_type: a.subject_type, subject_id: a.subject_id,
          owner_id: a.owner_id, due_at: a.due_at, status: a.status,
          completed_at: a.completed_at, created_at: a.created_at, updated_at: a.updated_at }
      end

      def product(product)
        { id: product.id, name: product.name, sku: product.sku, description: product.description,
          default_unit_price_cents: product.default_unit_price_cents, currency: product.currency,
          active: product.active, created_at: product.created_at, updated_at: product.updated_at }
      end

      def deal_line_item(item)
        { id: item.id, deal_id: item.deal_id, product_id: item.product_id,
          description: item.description, quantity: item.quantity.to_f,
          unit_price_cents: item.unit_price_cents, total_cents: item.total_cents,
          currency: item.currency, created_at: item.created_at, updated_at: item.updated_at }
      end

      def competitor(competitor)
        { id: competitor.id, name: competitor.name, website: competitor.website,
          notes: competitor.notes, created_at: competitor.created_at, updated_at: competitor.updated_at }
      end

      def campaign(campaign)
        {
          id: campaign.id, name: campaign.name, code: campaign.code,
          description: campaign.description, status: campaign.status, channel: campaign.channel,
          starts_on: campaign.starts_on, ends_on: campaign.ends_on,
          budget_cents: campaign.budget_cents, currency: campaign.currency,
          utm_source: campaign.utm_source, utm_medium: campaign.utm_medium,
          utm_campaign: campaign.utm_campaign,
          attributed_leads_count: campaign.attributed_leads.count,
          attributed_deals_count: campaign.attributed_deals.count,
          created_at: campaign.created_at, updated_at: campaign.updated_at
        }
      end

      def deal_contact_role(link)
        { id: link.id, deal_id: link.deal_id, contact_id: link.contact_id,
          contact_name: link.contact.name, role: link.role,
          created_at: link.created_at, updated_at: link.updated_at }
      end

      def deal_competitor(link)
        { id: link.id, deal_id: link.deal_id, competitor_id: link.competitor_id,
          competitor_name: link.competitor.name, disposition: link.disposition, notes: link.notes,
          created_at: link.created_at, updated_at: link.updated_at }
      end

      def pipeline(p)
        {
          id: p.id, name: p.name, slug: p.slug, position: p.position, active: p.active,
          stages: p.pipeline_stages.sort_by(&:position).map { |s|
            { id: s.id, name: s.name, position: s.position, probability: s.probability,
              is_won: s.is_won, is_lost: s.is_lost }
          },
          created_at: p.created_at, updated_at: p.updated_at
        }
      end

      def sequence(s)
        {
          id: s.id, name: s.name, active: s.active, owner_id: s.owner_id,
          business_calendar_id: s.business_calendar_id,
          steps: s.ordered_steps.map { |st|
            { id: st.id, position: st.position, delay_days: st.delay_days,
              delay_hours: st.delay_hours, use_business_hours: st.use_business_hours,
              template_key: st.template_key, channel: st.channel, subject: st.subject, body: st.body }
          },
          analytics: s.delivery_analytics,
          created_at: s.created_at, updated_at: s.updated_at
        }
      end

      def sequence_enrollment(e)
        latest_delivery = e.sequence_deliveries.order(created_at: :desc).first
        {
          id: e.id, sequence_id: e.sequence_id, enrollable_type: e.enrollable_type,
          enrollable_id: e.enrollable_id, status: e.status,
          current_step_position: e.current_step_position, next_run_at: e.next_run_at,
          last_delivery: latest_delivery && {
            status: latest_delivery.status, channel: latest_delivery.channel,
            claimed_at: latest_delivery.claimed_at, delivered_at: latest_delivery.delivered_at,
            opened_at: latest_delivery.opened_at, clicked_at: latest_delivery.clicked_at,
            replied_at: latest_delivery.replied_at, open_count: latest_delivery.open_count,
            click_count: latest_delivery.click_count, activity_id: latest_delivery.activity_id
          },
          created_at: e.created_at, updated_at: e.updated_at
        }
      end

      def queue(q)
        { id: q.id, name: q.name, slug: q.slug, description: q.description,
          member_ids: q.member_ids, created_at: q.created_at, updated_at: q.updated_at }
      end

      def category(c)
        { id: c.id, name: c.name, description: c.description,
          ai_auto_resolve: c.ai_auto_resolve, created_at: c.created_at, updated_at: c.updated_at }
      end

      def sla_policy(p)
        { id: p.id, name: p.name, description: p.description,
          business_calendar_id: p.business_calendar_id,
          targets: p.sla_targets.map { |t|
            { priority: t.priority, first_response_minutes: t.first_response_minutes,
              resolution_minutes: t.resolution_minutes }
          },
          created_at: p.created_at, updated_at: p.updated_at }
      end

      def business_calendar(calendar)
        {
          id: calendar.id, name: calendar.name, time_zone: calendar.time_zone,
          is_default: calendar.is_default,
          windows: calendar.business_calendar_windows.map { |window|
            { id: window.id, weekday: window.weekday,
              starts_at: window.starts_at, ends_at: window.ends_at }
          },
          exceptions: calendar.business_calendar_exceptions.map { |exception|
            { id: exception.id, on_date: exception.on_date, name: exception.name,
              closed: exception.closed, starts_at: exception.starts_at, ends_at: exception.ends_at }
          },
          created_at: calendar.created_at, updated_at: calendar.updated_at
        }
      end

      def custom_field_definition(definition)
        {
          id: definition.id, resource_type: definition.resource_type,
          key: definition.key, label: definition.label, field_type: definition.field_type,
          options: definition.options, required: definition.required,
          active: definition.active, reportable: definition.reportable,
          position: definition.position,
          created_at: definition.created_at, updated_at: definition.updated_at
        }
      end

      def macro(m)
        { id: m.id, name: m.name, body: m.body, message_kind: m.message_kind,
          set_status: m.set_status, set_priority: m.set_priority,
          set_queue_id: m.set_queue_id, set_assignee_id: m.set_assignee_id,
          created_at: m.created_at, updated_at: m.updated_at }
      end

      def reference_doc(d)
        { id: d.id, title: d.title, body: d.body, slug: d.slug, status: d.status,
          visibility: d.visibility, locale: d.locale, translation_key: d.translation_key,
          knowledge_category_id: d.knowledge_category_id,
          current_version: d.version_number, helpfulness: d.helpfulness_summary,
          created_at: d.created_at, updated_at: d.updated_at }
      end

      def reference_doc_version(version)
        { id: version.id, number: version.number, title: version.title, body: version.body,
          locale: version.locale, status: version.status, visibility: version.visibility,
          knowledge_category_id: version.knowledge_category_id,
          created_by_id: version.created_by_id, created_at: version.created_at }
      end

      def knowledge_category(category)
        { id: category.id, name: category.name, slug: category.slug,
          description: category.description, parent_id: category.parent_id,
          path: category.display_path, position: category.position,
          created_at: category.created_at, updated_at: category.updated_at }
      end

      def user(u)
        { id: u.id, name: u.name, email_address: u.email_address, role: u.role,
          active: u.active, locale: u.locale, email_signature: u.email_signature,
          queue_ids: u.queue_memberships.map(&:queue_id),
          record_read_scope: u.record_read_scope, record_write_scope: u.record_write_scope,
          team_ids: u.team_memberships.map(&:team_id),
          scoped_account_ids: u.account_memberships.map(&:organisation_id),
          created_at: u.created_at, updated_at: u.updated_at }
      end

      def audit_entry(e)
        { id: e.id, action: e.action, actor_type: e.actor_type, actor_id: e.actor_id,
          auditable_type: e.auditable_type, auditable_id: e.auditable_id,
          changeset: e.changeset, metadata: e.metadata,
          previous_sha: e.previous_sha, sha: e.sha, created_at: e.created_at }
      end

      def webhook_endpoint(w)
        { id: w.id, name: w.name, url: w.url, events: w.events, active: w.active,
          created_at: w.created_at, updated_at: w.updated_at }
      end

      def webhook_delivery(d)
        { id: d.id, webhook_endpoint_id: d.webhook_endpoint_id, event: d.event,
          status: d.status, attempts: d.attempts, response_code: d.response_code,
          last_error: d.last_error, delivered_at: d.delivered_at, created_at: d.created_at }
      end

      def service_account(s)
        grants = s.connector_grants.includes(:connector).map do |grant|
          { connector_id: grant.connector_id, connector_name: grant.connector.name, actions: grant.actions }
        end
        { id: s.id, name: s.name, description: s.description, client_id: s.client_id,
          scopes: s.scopes, connector_grants: grants, active: s.active,
          created_at: s.created_at, updated_at: s.updated_at }
      end

      def api_token(t)
        { id: t.id, user_id: t.user_id, name: t.name, last_used_at: t.last_used_at,
          revoked_at: t.revoked_at, created_at: t.created_at }
      end

      def approval_request(r)
        return nil if r.nil?
        { id: r.id, status: r.status, requested_action: r.requested_action,
          subject_type: r.subject_type, subject_id: r.subject_id,
          approval_process_id: r.approval_process_id, requested_by_id: r.requested_by_id,
          created_at: r.created_at }
      end

      def decision(d)
        { id: d.id, rule: d.rule, version: d.version, signal: d.signal,
          decision_class: d.decision_class, status: d.status, action: d.action,
          action_params: d.action_params, effect: d.effect,
          recommendation: d.recommendation, reasoning: d.reasoning,
          subject_type: d.subject_type, subject_id: d.subject_id, subject_label: d.subject_label,
          approved_by_id: d.approved_by_id, decision_reason: d.decision_reason,
          decided_at: d.decided_at, appealable: d.appealable?,
          created_at: d.created_at, updated_at: d.updated_at }
      end
    end
  end
end
