module Admin
  # Chain-verification status page (handoff §6).
  class AuditController < ApplicationController
    def show
      authorize :audit, policy_class: AdminAreaPolicy
      scope = AuditEntry.visible_to(Current.user) # tenant-scoped unless super_admin / isolated (C1)
      @entry_count = scope.count
      @latest_entry = scope.order(:id).last
      # Global chain verification (and its platform-wide count) is super_admin-only.
      @verification = AuditEntry.verify_chain if AuditEntry.global_view?(Current.user)
    end
  end
end
