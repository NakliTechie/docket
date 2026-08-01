class BusinessCalendarsController < ApplicationController
  require_feature "service_desk"
  before_action :set_calendar, only: %i[edit update destroy]

  def index
    authorize BusinessCalendar
    @business_calendars = policy_scope(BusinessCalendar)
      .includes(:business_calendar_windows, :business_calendar_exceptions).order(:name)
  end

  def new
    @business_calendar = BusinessCalendar.new(time_zone: "UTC",
                                               is_default: BusinessCalendar.none?)
    (1..5).each do |weekday|
      @business_calendar.business_calendar_windows.build(
        weekday: weekday, starts_minute: 540, ends_minute: 1020
      )
    end
    prepare_nested_rows
    authorize @business_calendar
  end

  def create
    @business_calendar = BusinessCalendar.new(calendar_params)
    authorize @business_calendar
    if @business_calendar.save
      redirect_to business_calendars_path, notice: t(".created")
    else
      prepare_nested_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @business_calendar
    prepare_nested_rows
  end

  def update
    authorize @business_calendar
    if @business_calendar.update(calendar_params)
      redirect_to business_calendars_path, notice: t(".updated")
    else
      prepare_nested_rows
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @business_calendar
    if @business_calendar.destroy
      redirect_to business_calendars_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to business_calendars_path,
                  alert: @business_calendar.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  private

  def set_calendar
    @business_calendar = policy_scope(BusinessCalendar).find(params[:id])
  end

  def prepare_nested_rows
    2.times { @business_calendar.business_calendar_windows.build }
    3.times { @business_calendar.business_calendar_exceptions.build }
  end

  def calendar_params
    params.require(:business_calendar).permit(
      :name, :time_zone, :is_default,
      business_calendar_windows_attributes: %i[id weekday starts_at ends_at _destroy],
      business_calendar_exceptions_attributes: %i[id on_date name closed starts_at ends_at _destroy]
    )
  end
end
