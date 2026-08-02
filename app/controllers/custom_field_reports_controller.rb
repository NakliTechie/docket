class CustomFieldReportsController < ApplicationController
  def index
    @resource_type = normalized_resource_type
    authorize @resource_type, :index?, policy_class: CustomFieldReportPolicy
    ensure_feature!(@resource_type == "cases" ? "service_desk" : "work")
    @definitions = CustomFieldDefinition.for_resource(@resource_type).reportable.ordered
    @definition = selected_definition
    @report = CustomFieldReport.new(definition: @definition, scope: report_scope) if @definition

    respond_to do |format|
      format.html
      format.csv do
        authorize @resource_type, :export?, policy_class: CustomFieldReportPolicy
        return head :not_found unless @report

        send_data @report.to_csv,
                  filename: "docket-#{@resource_type}-#{@definition.key}-#{Date.current}.csv"
      end
    end
  end

  private

  def normalized_resource_type
    value = params[:resource_type].presence || "cases"
    return value if CustomFieldDefinition::RESOURCE_TYPES.include?(value)

    raise ActionController::BadRequest, "unsupported custom-field resource"
  end

  def selected_definition
    return @definitions.first if params[:field].blank?

    @definitions.find_by!(key: params[:field])
  end

  def report_scope
    @resource_type == "cases" ? policy_scope(Case) : policy_scope(WorkItem)
  end
end
