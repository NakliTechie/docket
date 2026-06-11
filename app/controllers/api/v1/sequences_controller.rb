module Api
  module V1
    class SequencesController < BaseController
      before_action :set_sequence, only: %i[show update destroy]

      def index
        pagy, records = pagy(api_scope(Sequence, scope: "crm:read").order(:name))
        render json: { data: records.map { |s| Serialize.sequence(s) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@sequence, :show?, scope: "crm:read")
        render json: { data: Serialize.sequence(@sequence) }
      end

      def create
        authorize_api!(Sequence.new, :create?, scope: "crm:write")
        sequence = Sequence.new(sequence_params)
        if sequence.save
          render json: { data: Serialize.sequence(sequence) }, status: :created
        else
          render_validation_errors(sequence)
        end
      end

      def update
        authorize_api!(@sequence, :update?, scope: "crm:write")
        if @sequence.update(sequence_params)
          render json: { data: Serialize.sequence(@sequence) }
        else
          render_validation_errors(@sequence)
        end
      end

      def destroy
        authorize_api!(@sequence, :destroy?, scope: "crm:write")
        @sequence.destroy
        head :no_content
      end

      private

      def set_sequence
        @sequence = Sequence.find(params[:id])
      end

      def sequence_params
        params.require(:sequence).permit(:name, :active,
          sequence_steps_attributes: %i[id position delay_days channel subject body _destroy])
      end
    end
  end
end
