module Api
  module V1
    class OrganisationsController < BaseController
      before_action :set_organisation, only: %i[show update destroy]

      def index
        pagy, records = pagy(api_scope(Organisation, scope: "organisations:read").order(:name))
        render json: { data: records.map { |o| Serialize.organisation(o) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@organisation, :show?, scope: "organisations:read")
        render json: { data: Serialize.organisation(@organisation) }
      end

      def create
        authorize_api!(Organisation.new, :create?, scope: "organisations:write")
        organisation = Organisation.new(organisation_params)
        if organisation.save
          render json: { data: Serialize.organisation(organisation) }, status: :created
        else
          render_validation_errors(organisation)
        end
      end

      def update
        authorize_api!(@organisation, :update?, scope: "organisations:write")
        if @organisation.update(organisation_params)
          render json: { data: Serialize.organisation(@organisation) }
        else
          render_validation_errors(@organisation)
        end
      end

      def destroy
        authorize_api!(@organisation, :destroy?, scope: "organisations:write")
        @organisation.destroy
        head :no_content
      end

      private

      def set_organisation
        @organisation = Organisation.find(params[:id])
      end

      def organisation_params
        params.require(:organisation).permit(:name, :kind, :external_ref, :notes)
      end
    end
  end
end
