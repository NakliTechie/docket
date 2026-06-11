module Api
  module V1
    class SequenceEnrollmentsController < BaseController
      before_action :set_enrollment, only: %i[show cancel]

      def index
        scope = api_scope(SequenceEnrollment, scope: "crm:read")
        scope = scope.where(sequence_id: params[:sequence_id]) if params[:sequence_id].present?
        pagy, records = pagy(scope.order(created_at: :desc))
        render json: { data: records.map { |e| Serialize.sequence_enrollment(e) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@enrollment.sequence, :show?, scope: "crm:read")
        render json: { data: Serialize.sequence_enrollment(@enrollment) }
      end

      def create
        sequence = Sequence.find(params[:sequence_id])
        authorize_api!(sequence, :enroll?, scope: "crm:write")
        target = find_enrollable
        return render_error("invalid_enrollable", status: :unprocessable_entity) unless target

        enrollment = sequence.enroll!(target)
        render json: { data: Serialize.sequence_enrollment(enrollment) }, status: :created
      end

      def cancel
        authorize_api!(@enrollment.sequence, :enroll?, scope: "crm:write")
        @enrollment.cancel!
        render json: { data: Serialize.sequence_enrollment(@enrollment) }
      end

      private

      def set_enrollment
        @enrollment = SequenceEnrollment.find(params[:id])
      end

      def find_enrollable
        case params[:enrollable_type]
        when "Lead"    then Lead.find_by(id: params[:enrollable_id])
        when "Contact" then Contact.find_by(id: params[:enrollable_id])
        end
      end
    end
  end
end
