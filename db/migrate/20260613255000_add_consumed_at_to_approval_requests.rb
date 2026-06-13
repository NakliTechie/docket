# H4 (forward pass 2026-06-13): an approved maker-checker request was never
# retired, so once a guarded transition (e.g. case closure) was approved it
# stayed "cleared" forever — after reopen→reclose the maker could re-close with
# no fresh sign-off. consumed_at marks an approval as spent (set when the action
# is carried out); the clearance check ignores consumed approvals.
class AddConsumedAtToApprovalRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :approval_requests, :consumed_at, :datetime
  end
end
