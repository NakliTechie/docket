module Api
  module V1
    # OAuth2 client-credentials grant for service accounts.
    class OauthController < ActionController::API
      def token
        unless params[:grant_type] == "client_credentials"
          return render json: { error: "unsupported_grant_type" }, status: :bad_request
        end

        client_id, client_secret = client_credentials
        account = ServiceAccount.authenticate(client_id.to_s, client_secret.to_s)
        unless account
          return render json: { error: "invalid_client" }, status: :unauthorized
        end

        token = account.issue_access_token!
        AuditEntry.append!(action: "service_account.token_issued", auditable: account, actor: account,
                           metadata: { ip: request.remote_ip })
        render json: {
          access_token: token.raw_token,
          token_type: "Bearer",
          expires_in: (token.expires_at - Time.current).to_i,
          scope: token.scopes.join(" ")
        }
      end

      private

      # Accepts HTTP Basic (per RFC 6749) or body params.
      def client_credentials
        if request.authorization.to_s.start_with?("Basic ")
          decoded = Base64.decode64(request.authorization.split(" ", 2).last)
          decoded.split(":", 2)
        else
          [ params[:client_id], params[:client_secret] ]
        end
      end
    end
  end
end
