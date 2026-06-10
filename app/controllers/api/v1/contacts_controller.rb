module Api
  module V1
    class ContactsController < BaseController
      before_action :set_contact, only: %i[show update destroy]

      def index
        scope = api_scope(Contact, scope: "contacts:read").search(params[:q])
        scope = scope.where(external_id: params[:external_id]) if params[:external_id].present?
        scope = scope.where(organisation_id: params[:organisation_id]) if params[:organisation_id].present?
        pagy, records = pagy(scope.order(:name))
        render json: { data: records.map { |c| Serialize.contact(c) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@contact, :show?, scope: "contacts:read")
        render json: { data: Serialize.contact(@contact) }
      end

      def create
        authorize_api!(Contact.new, :create?, scope: "contacts:write")
        contact = Contact.new(contact_params)
        if contact.save
          render json: { data: Serialize.contact(contact) }, status: :created
        else
          render_validation_errors(contact)
        end
      end

      def update
        authorize_api!(@contact, :update?, scope: "contacts:write")
        if @contact.update(contact_params)
          render json: { data: Serialize.contact(@contact) }
        else
          render_validation_errors(@contact)
        end
      end

      def destroy
        authorize_api!(@contact, :destroy?, scope: "contacts:write")
        if @contact.destroy
          head :no_content
        else
          render_validation_errors(@contact)
        end
      end

      private

      def set_contact
        @contact = if params[:id].to_s.start_with?("ext:")
          Contact.find_by!(external_id: params[:id].delete_prefix("ext:"))
        else
          Contact.find(params[:id])
        end
      end

      def contact_params
        params.require(:contact).permit(:name, :email, :phone, :external_id,
                                        :organisation_id, :preferred_language, :notes)
      end
    end
  end
end
