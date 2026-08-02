module Api
  module V1
    class CrmMessagesController < BaseController
      require_feature "crm"

      def index
        subject = find_subject
        authorize_api!(subject, :show?, scope: read_scope(subject))
        entries = CrmConversation.call(subject, case_scope: readable_case_scope,
                                        contact_scope: readable_record_scope(Contact, scope: "contacts:read"),
                                        lead_scope: readable_record_scope(Lead, scope: "crm:read"),
                                        deal_scope: readable_record_scope(Deal, scope: "crm:read"),
                                        visible_types: readable_crm_types)
        render json: { data: entries.map { |entry| Serialize.crm_conversation_entry(entry) } }
      end

      def create
        subject = find_subject
        authorize_api!(subject, :update?, scope: write_scope(subject))
        message = CrmMessage.compose(
          subject: subject,
          author: Current.actor,
          subject_line: message_params[:subject_line],
          body: message_params[:body]
        )
        render json: { data: Serialize.crm_message(message) }, status: :created
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      end

      private

      def find_subject
        type = params.require(:subject_type)
        raise ActiveRecord::RecordNotFound unless CrmMessage::SUBJECT_TYPES.include?(type)

        type.constantize.find(params.require(:subject_id))
      end

      def read_scope(subject) = subject.is_a?(Contact) ? "contacts:read" : "crm:read"
      def write_scope(subject) = subject.is_a?(Contact) ? "contacts:write" : "crm:write"

      def readable_case_scope
        return Case.none unless Features.enabled?("service_desk")
        return policy(Case).index? ? policy_scope(Case) : Case.none if current_user

        current_access_token.scope?("cases:read") ? Case.all : Case.none
      end

      def readable_record_scope(model, scope:)
        return policy(model).index? ? policy_scope(model) : model.none if current_user

        current_access_token.scope?(scope) ? model.all : model.none
      end

      def readable_crm_types
        return human_readable_crm_types if current_user

        types = []
        types << "Contact" if current_access_token.scope?("contacts:read")
        types.concat(%w[Lead Deal]) if current_access_token.scope?("crm:read")
        types
      end

      def human_readable_crm_types
        types = []
        types << "Contact" if policy(Contact).index?
        types << "Lead" if policy(Lead).index?
        types << "Deal" if policy(Deal).index?
        types
      end

      def message_params
        params.require(:crm_message).permit(:subject_line, :body)
      end
    end
  end
end
