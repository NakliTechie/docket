module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_tenant

    def connect
      set_current_tenant
      ActsAsTenant.with_tenant(current_tenant) { set_current_user }
    end

    private
      def set_current_tenant
        tenant = Tenant.resolve_by_host(request.host)
        reject_unauthorized_connection if tenant.nil? || tenant.suspended?
        self.current_tenant = tenant
      end

      def set_current_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          user = session.user
          if session.expired?
            session.destroy
            cookies.delete(:session_id)
          elsif user&.active? && user.tenant_id == current_tenant.id
            self.current_user = user
          end
        end
      end
  end
end
