module Api
  module V1
    class AuditController < BaseController
      def entries
        require_audit_access!
        # Tenant-scoped unless the caller is super_admin / an isolated deploy (C1).
        scope = AuditEntry.visible_to(current_user).order(id: :desc)
        scope = scope.where(action: params[:action_name]) if params[:action_name].present?
        scope = scope.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?
        scope = scope.where(auditable_id: params[:auditable_id]) if params[:auditable_id].present?
        pagy, records = pagy(scope)
        render json: { data: records.map { |e| Serialize.audit_entry(e) }, pagination: pagination_meta(pagy) }
      end

      def verification
        require_audit_access!
        # The chain is global; verifying it exposes the platform-wide count, so
        # it's a super_admin / isolated capability only (C1).
        raise Pundit::NotAuthorizedError unless AuditEntry.global_view?(current_user)
        render json: { data: AuditEntry.verify_chain }
      end

      private

      def require_audit_access!
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.can?("audit:read")
        else
          raise ScopeDenied, "audit:read" unless current_access_token.scope?("audit:read")
        end
      end
    end
  end
end
