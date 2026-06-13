module Admin
  # The OAuth2 authorization-code connect flow for OAuth connectors
  # (Connectors::OauthProvider). #oauth_authorize redirects the admin's browser
  # to the vendor; the vendor redirects back to #oauth_callback with a code and
  # our signed state, which we exchange for an access+refresh token bundle stored
  # on the connector. State is a short-lived signed token (CSRF + binds the
  # callback to the connector that initiated it).
  class ConnectorOauthController < ApplicationController
    STATE_PURPOSE = "connector_oauth".freeze

    # GET /admin/connectors/:id/oauth_authorize
    def oauth_authorize
      connector = Connector.find(params[:id])
      authorize connector, :update?
      unless connector.oauth? && connector.configured?
        return redirect_to admin_connector_path(connector), alert: t(".not_ready")
      end

      state = state_verifier.generate({ "cid" => connector.id }, expires_in: 15.minutes)
      url = Connectors::Registry.klass(connector.provider).authorize_url(connector, redirect_uri: callback_url, state: state)
      redirect_to url, allow_other_host: true
    end

    # GET /admin/connectors/oauth_callback?code=&state=
    def oauth_callback
      data = verify_state
      return if performed? # invalid/expired state already redirected

      connector = Connector.find(data["cid"])
      authorize connector, :update?

      if params[:error].present?
        return redirect_to admin_connector_path(connector), alert: t(".denied", error: params[:error].to_s.truncate(120))
      end

      connector.provider_instance.exchange_code!(params[:code].to_s, redirect_uri: callback_url)
      connector.update!(status: :active)
      redirect_to admin_connector_path(connector), notice: t(".connected")
    rescue ActiveRecord::RecordNotFound
      skip_authorization
      redirect_to admin_connectors_path, alert: t(".bad_state")
    rescue Connectors::Error => e
      redirect_to admin_connector_path(connector), alert: t(".exchange_failed", error: e.message)
    end

    private

    def verify_state
      state_verifier.verify(params[:state].to_s)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      skip_authorization
      redirect_to admin_connectors_path, alert: t(".bad_state")
      nil
    end

    # The single, connector-agnostic redirect URI the operator registers in
    # their OAuth app. The connector is identified via the signed state.
    def callback_url
      URI.join(Sso.base_url, oauth_callback_admin_connectors_path).to_s
    end

    def state_verifier
      Rails.application.message_verifier(STATE_PURPOSE)
    end
  end
end
