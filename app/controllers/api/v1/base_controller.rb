module Api
  module V1
    # API auth has two shapes (handoff §5):
    #   dkt_…  per-user token — full console parity via Pundit policies
    #   dkts_… service-account bearer (client credentials) — scope-gated
    class BaseController < ActionController::API
      include Pundit::Authorization
      include Pagy::Backend

      class ScopeDenied < StandardError; end
      class AttachmentError < StandardError; end

      before_action :authenticate!
      before_action :set_current_context

      rescue_from ActiveRecord::RecordNotFound do
        render_error("not_found", status: :not_found)
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        # e.g. an on-behalf-of Contact.create! with a bad email — 422, not 500.
        render_validation_errors(e.record)
      end
      rescue_from Pundit::NotAuthorizedError, ScopeDenied do
        render_error("forbidden", status: :forbidden)
      end
      rescue_from ActionController::ParameterMissing do |e|
        render_error("missing_parameter", detail: e.param.to_s, status: :bad_request)
      end
      rescue_from Case::InvalidTransition do |e|
        render_error("invalid_transition", detail: e.message, status: :unprocessable_entity)
      end
      rescue_from AttachmentError do |e|
        render_error("invalid_attachment", detail: e.message, status: :unprocessable_entity)
      end

      private

      attr_reader :current_api_token, :current_access_token

      def authenticate!
        raw = bearer_token
        if raw&.start_with?("#{ApiToken::PREFIX}_")
          @current_api_token = ApiToken.authenticate(raw)
          return if @current_api_token
        elsif raw&.start_with?("#{OauthAccessToken::PREFIX}_")
          @current_access_token = OauthAccessToken.authenticate(raw)
          return if @current_access_token
        end
        render_error("unauthorized", status: :unauthorized)
      end

      def bearer_token
        # Scheme is case-insensitive (RFC 7235); tolerate extra whitespace
        # and capture just the token.
        request.authorization.to_s[/\ABearer\s+(\S+)/i, 1]
      end

      def current_user
        current_api_token&.user
      end

      def service_account
        current_access_token&.service_account
      end

      def pundit_user
        current_user
      end

      def set_current_context
        Current.actor = service_account || current_user
        Current.request_id = request.request_id
        Current.ip_address = request.remote_ip
      end

      # Human tokens carry the user's console permissions (Pundit).
      # Service accounts must hold the named scope.
      def authorize_api!(record, query, scope:)
        if current_user
          authorize(record, query)
        elsif scope.nil? || !current_access_token.scope?(scope)
          raise ScopeDenied, scope.to_s
        end
      end

      def api_scope(model, scope:)
        if current_user
          policy_scope(model)
        elsif current_access_token.scope?(scope)
          model.all
        else
          raise ScopeDenied, scope
        end
      end

      # Scoped service accounts may attribute work to a Contact by the
      # operator's own customer identifier (handoff §5 on-behalf-of).
      def resolve_on_behalf_contact!
        external_id = params[:on_behalf_of].to_s.strip
        return nil if external_id.blank?

        # OBO attributes/creates a Contact — require the write capability
        # for BOTH human tokens (via ContactPolicy) and service accounts
        # (via scope). Previously only service accounts were checked, so a
        # user token whose user can't manage contacts could still upsert
        # one (M23).
        authorize_api!(Contact.new, :create?, scope: "contacts:write")

        contact = Contact.find_by(external_id: external_id)
        contact ||= Contact.create!(
          name: params.dig(:contact, :name).presence || external_id,
          email: params.dig(:contact, :email).presence,
          phone: params.dig(:contact, :phone).presence,
          external_id: external_id
        )
        Current.on_behalf_of = external_id
        contact
      end

      # Attachments arrive either as multipart uploads (files[]) or as
      # base64 JSON objects (attachments: [{filename, content_type,
      # data}]). Size/type/count limits are enforced by
      # AttachableValidation on the model; oversized base64 is rejected
      # before decoding.
      MAX_ENCODED_ATTACHMENT_BYTES = (AttachableValidation::MAX_FILE_SIZE * 4 / 3) + 8

      def extract_attachments(container)
        return [] if container.blank?

        uploads = Array(container[:files]).select { |f| f.respond_to?(:original_filename) }
        encoded_inputs = Array(container[:attachments])
        # Reject by count BEFORE decoding so a flood of base64 blobs can't
        # be decoded into memory — the model's MAX_FILES check runs too
        # late (after every blob is already decoded).
        if uploads.size + encoded_inputs.size > AttachableValidation::MAX_FILES
          raise AttachmentError, "too many attachments (max #{AttachableValidation::MAX_FILES})"
        end
        encoded = encoded_inputs.map do |attachment|
          attachment = attachment.permit(:filename, :content_type, :data) if attachment.respond_to?(:permit)
          data = attachment[:data].to_s
          raise AttachmentError, "attachment too large" if data.bytesize > MAX_ENCODED_ATTACHMENT_BYTES
          begin
            io = StringIO.new(Base64.strict_decode64(data))
          rescue ArgumentError
            raise AttachmentError, "attachment data must be base64"
          end
          {
            io: io,
            filename: attachment[:filename].to_s.presence || "attachment",
            content_type: attachment[:content_type].to_s.presence || "application/octet-stream"
          }
        end
        uploads + encoded
      end

      def render_error(code, status:, detail: nil)
        render json: { error: code, detail: detail }.compact, status: status
      end

      def render_validation_errors(record)
        render json: { error: "validation_failed", details: record.errors.full_messages },
               status: :unprocessable_entity
      end

      def pagination_meta(pagy)
        { page: pagy.page, pages: pagy.pages, count: pagy.count, per_page: pagy.limit }
      end
    end
  end
end
