module Api
  module V1
    class MacrosController < BaseController
      before_action :set_macro, only: %i[show update destroy]

      def index
        records = api_scope(Macro, scope: "config:read").order(:name)
        render json: { data: records.map { |m| Serialize.macro(m) } }
      end

      def show
        authorize_api!(@macro, :show?, scope: "config:read")
        render json: { data: Serialize.macro(@macro) }
      end

      def create
        authorize_api!(Macro.new, :create?, scope: "config:write")
        macro = Macro.new(macro_params)
        if macro.save
          render json: { data: Serialize.macro(macro) }, status: :created
        else
          render_validation_errors(macro)
        end
      end

      def update
        authorize_api!(@macro, :update?, scope: "config:write")
        if @macro.update(macro_params)
          render json: { data: Serialize.macro(@macro) }
        else
          render_validation_errors(@macro)
        end
      end

      def destroy
        authorize_api!(@macro, :destroy?, scope: "config:write")
        @macro.destroy
        head :no_content
      end

      private

      def set_macro
        @macro = Macro.find(params[:id])
      end

      def macro_params
        params.require(:macro).permit(:name, :body)
      end
    end
  end
end
