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
          contact_id: c.contact_id,
          sla_policy_id: c.sla_policy_id,
          first_response_due_at: c.first_response_due_at,
          resolution_due_at: c.resolution_due_at,
          first_responded_at: c.first_responded_at,
          resolved_at: c.resolved_at,
          closed_at: c.closed_at,
          first_response_breached: c.first_response_breached,
          resolution_breached: c.resolution_breached,
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
          metadata: m.metadata,
          attachments: m.files.map { |f| { filename: f.filename.to_s, content_type: f.content_type, byte_size: f.byte_size } },
          created_at: m.created_at
        }
      end

      def contact(c)
        {
          id: c.id, name: c.name, email: c.email, phone: c.phone,
          external_id: c.external_id, organisation_id: c.organisation_id,
          preferred_language: c.preferred_language, notes: c.notes,
          created_at: c.created_at, updated_at: c.updated_at
        }
      end

      def organisation(o)
        { id: o.id, name: o.name, kind: o.kind, external_ref: o.external_ref,
          notes: o.notes, created_at: o.created_at, updated_at: o.updated_at }
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
          targets: p.sla_targets.map { |t|
            { priority: t.priority, first_response_minutes: t.first_response_minutes,
              resolution_minutes: t.resolution_minutes }
          },
          created_at: p.created_at, updated_at: p.updated_at }
      end

      def macro(m)
        { id: m.id, name: m.name, body: m.body, created_at: m.created_at, updated_at: m.updated_at }
      end

      def reference_doc(d)
        { id: d.id, title: d.title, body: d.body, created_at: d.created_at, updated_at: d.updated_at }
      end

      def user(u)
        { id: u.id, name: u.name, email_address: u.email_address, role: u.role,
          active: u.active, locale: u.locale, queue_ids: u.queue_memberships.map(&:queue_id),
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
        { id: s.id, name: s.name, description: s.description, client_id: s.client_id,
          scopes: s.scopes, active: s.active, created_at: s.created_at, updated_at: s.updated_at }
      end

      def api_token(t)
        { id: t.id, user_id: t.user_id, name: t.name, last_used_at: t.last_used_at,
          revoked_at: t.revoked_at, created_at: t.created_at }
      end
    end
  end
end
