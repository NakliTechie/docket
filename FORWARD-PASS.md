# Forward Pass Log

One line per finding fixed during gate forward passes: gate, finding, fix, commit.

- G1 · `/admin/users` returned 200 (empty list) to non-admins because index relied on policy_scope alone · added class-level `authorize User` on index + integration test · (G1 commit)
- G1 · `case[status]` could be mass-assigned around the state machine · status excluded from permitted params, model-level guard validates all status changes go through `transition_to!` + tests · (G1 commit)
- G1 · staff composer could forge `agent_turn` messages · MessagesController whitelists kind to public_reply/internal_note + test · (G1 commit)
- G1 · deactivated/soft-deleted users could resume existing sessions · `find_session_by_cookie` now checks `user.active?` (soft-deleted users vanish via default scope); `deactivate!` destroys sessions + tests · (G1 commit)
- G1 · `dependent: :nullify` on soft-deleting parents would have NULLed `cases.contact_id` (NOT NULL) and erased history · associations changed to `restrict_with_error` (contact↔cases) / no-dependent + `with_deleted` belongs_to scopes + tests · (G1 commit)
- G1 · Brakeman: role mass-assignment in Admin::UsersController · justified ignore (admin-only controller, Pundit-enforced, tested) in `config/brakeman.ignore` · (G1 commit)
