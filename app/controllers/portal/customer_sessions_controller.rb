module Portal
  # Customer SSO (handoff §5A): the portal trusts the deployment's
  # customer IdP; the configured claim maps to Contact.external_id.
  # Grants portal-level access only — the customer session lives in the
  # Rails session cookie (:portal_contact_id) and can never reach the
  # staff console, whose guard reads only the signed :session_id cookie.
  class CustomerSessionsController < BaseController
    skip_before_action :verify_authenticity_token, only: :create

    def create
      auth = request.env["omniauth.auth"]
      external_id = extract_external_id(auth)
      if external_id.blank?
        return redirect_to portal_root_path, alert: t("portal.customer.sso_failed")
      end

      contact = Contact.find_by(external_id: external_id) || provision_contact(auth, external_id)
      session[:portal_contact_id] = contact.id
      AuditEntry.append!(action: "contact.login_sso", auditable: contact, actor: contact,
                         metadata: { ip: request.remote_ip })
      redirect_to portal_my_cases_path, notice: t("portal.customer.signed_in", name: contact.name)
    end

    def destroy
      session.delete(:portal_contact_id)
      redirect_to portal_root_path, notice: t("portal.customer.signed_out")
    end

    private

    def extract_external_id(auth)
      claim = Sso.customer_external_id_claim
      value = claim == "sub" ? auth&.uid : (auth&.extra&.raw_info&.[](claim) || auth&.info&.[](claim))
      value.to_s.strip.presence
    end

    def provision_contact(auth, external_id)
      Contact.create!(
        name: auth.info&.name.presence || external_id,
        email: auth.info&.email.to_s.strip.downcase.presence,
        external_id: external_id,
        preferred_language: I18n.locale.to_s
      )
    end
  end
end
