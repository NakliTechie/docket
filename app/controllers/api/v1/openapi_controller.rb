module Api
  module V1
    class OpenapiController < ActionController::API
      def show
        render json: Docket::Openapi.document
      end
    end
  end
end
