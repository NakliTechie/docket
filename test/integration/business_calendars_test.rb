require "test_helper"

class BusinessCalendarsTest < ActionDispatch::IntegrationTest
  test "configuration managers can create and edit calendars" do
    sign_in_as users(:client_admin)

    get business_calendars_path
    assert_response :success

    assert_difference "BusinessCalendar.count", 1 do
      post business_calendars_path, params: { business_calendar: {
        name: "India support", time_zone: "Chennai", is_default: "1",
        business_calendar_windows_attributes: {
          "0" => { weekday: "1", starts_at: "09:00", ends_at: "18:00" },
          "1" => { weekday: "", starts_at: "", ends_at: "" }
        },
        business_calendar_exceptions_attributes: {
          "0" => { on_date: "", name: "", closed: "0", starts_at: "", ends_at: "" }
        }
      } }
    end
    calendar = BusinessCalendar.find_by!(name: "India support")
    assert_redirected_to business_calendars_path
    assert_equal 1, calendar.business_calendar_windows.count
    assert_empty calendar.business_calendar_exceptions

    patch business_calendar_path(calendar), params: {
      business_calendar: { name: "India service", time_zone: "Chennai" }
    }
    assert_redirected_to business_calendars_path
    assert_equal "India service", calendar.reload.name
  end

  test "customer-service users can inspect but cannot change calendars" do
    sign_in_as users(:customer_service)

    get business_calendars_path
    assert_response :success
    get new_business_calendar_path
    assert_response :forbidden
    assert_no_difference "BusinessCalendar.count" do
      post business_calendars_path, params: { business_calendar: { name: "Nope" } }
    end
  end
end
