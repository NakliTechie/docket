module Admin
  # Chain-verification status page (handoff §6).
  class AuditController < ApplicationController
    def show
      authorize :audit, policy_class: AdminAreaPolicy
      @entry_count = AuditEntry.count
      @latest_entry = AuditEntry.order(:id).last
      @verification = AuditEntry.verify_chain
    end
  end
end
