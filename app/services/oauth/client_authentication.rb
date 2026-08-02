module Oauth
  module ClientAuthentication
    module_function

    def call(params:, authorization:)
      client_id, secret, method = credentials(params, authorization)
      client = OauthClient.active.find_by(client_id: client_id.to_s)
      raise Error.new("invalid_client", nil, status: :unauthorized) unless client
      unless client.token_endpoint_auth_method == method && client.authenticate_secret(secret)
        raise Error.new("invalid_client", nil, status: :unauthorized)
      end

      client
    end

    def credentials(params, authorization)
      if authorization.to_s.start_with?("Basic ")
        decoded = Base64.strict_decode64(authorization.split(" ", 2).last)
        client_id, secret = decoded.split(":", 2)
        [ client_id, secret, "client_secret_basic" ]
      elsif params[:client_secret].present?
        [ params[:client_id], params[:client_secret], "client_secret_post" ]
      else
        [ params[:client_id], nil, "none" ]
      end
    rescue ArgumentError
      raise Error.new("invalid_client", nil, status: :unauthorized)
    end
    private_class_method :credentials
  end
end
