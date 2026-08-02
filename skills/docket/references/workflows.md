# Docket workflow map

## Triage a case

Read `get_cases_id`, `get_cases_case_id_messages`, and the linked contact. Propose routing, ownership, priority, category, and next status. Use `post_cases_id_assign` or `post_cases_id_transition` only after the requested confirmation boundary.

## Resolve a case

Read the case and messages. Use the summary and reply-assist tools as drafts. Ground factual guidance in published reference documents. Record an approved response with `post_cases_case_id_messages`, then use a legal transition.

## Build Customer 360

Read `get_contacts_id` first. Follow only identifiers returned by Docket into cases, organisations, leads, deals, activities, and work. Separate current obligations from historical events.

## Qualify a lead

Read `get_leads_id` and related activity, campaign, and pipeline context. Explain stored scoring signals. Use `post_leads_id_convert` only after explicit confirmation.

## Review decisions

Read the decision and subject state. Check decision class, reasoning, reviewer identity, and appeal state. Preserve distinct-human maker-checker controls. Use approve or reject tools only after evidence review.

## Report operational health

Use activity, CSAT, sales, sprint, and dashboard decision-quality data for an explicit date window. Report exact counts. Name owners by role when recommending follow-up work.
