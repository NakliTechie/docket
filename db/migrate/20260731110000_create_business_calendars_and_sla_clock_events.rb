class CreateBusinessCalendarsAndSlaClockEvents < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :business_calendars do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :time_zone, null: false, default: "UTC"
      t.boolean :is_default, null: false, default: false
      t.timestamps
    end
    add_index :business_calendars, :tenant_id, unique: true,
              where: "is_default = TRUE", name: "index_business_calendars_one_default"

    create_table :business_calendar_windows do |t|
      t.references :business_calendar, null: false, foreign_key: true
      t.integer :weekday, null: false
      t.integer :starts_minute, null: false
      t.integer :ends_minute, null: false
      t.timestamps
    end
    add_index :business_calendar_windows,
              %i[business_calendar_id weekday starts_minute ends_minute],
              unique: true, name: "index_business_calendar_windows_unique"
    add_check_constraint :business_calendar_windows, "weekday BETWEEN 0 AND 6",
                         name: "business_calendar_windows_weekday_valid"
    add_check_constraint :business_calendar_windows,
                         "starts_minute >= 0 AND ends_minute <= 1440 AND starts_minute < ends_minute",
                         name: "business_calendar_windows_minutes_valid"

    create_table :business_calendar_exceptions do |t|
      t.references :business_calendar, null: false, foreign_key: true
      t.date :on_date, null: false
      t.string :name, null: false
      t.boolean :closed, null: false, default: true
      t.integer :starts_minute
      t.integer :ends_minute
      t.timestamps
    end
    add_index :business_calendar_exceptions, %i[business_calendar_id on_date], unique: true,
              name: "index_business_calendar_exceptions_unique"
    add_check_constraint :business_calendar_exceptions,
                         "(closed = TRUE AND starts_minute IS NULL AND ends_minute IS NULL) OR " \
                         "(closed = FALSE AND starts_minute >= 0 AND ends_minute <= 1440 AND starts_minute < ends_minute)",
                         name: "business_calendar_exceptions_shape_valid"

    add_reference :sla_policies, :business_calendar, foreign_key: true
    add_column :cases, :resolution_paused_at, :datetime
    add_column :cases, :resolution_remaining_minutes, :integer
    add_check_constraint :cases, "resolution_remaining_minutes >= 0",
                         name: "cases_resolution_remaining_minutes_nonnegative"

    create_table :sla_clock_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :case, null: false, foreign_key: true
      t.integer :clock_kind, null: false
      t.integer :event_kind, null: false
      t.datetime :occurred_at, null: false
      t.integer :remaining_minutes
      t.string :reason
      t.column :metadata, json_type
      t.timestamps
    end
    add_index :sla_clock_events, %i[case_id clock_kind occurred_at],
              name: "index_sla_clock_events_timeline"
    add_check_constraint :sla_clock_events, "remaining_minutes >= 0",
                         name: "sla_clock_events_remaining_nonnegative"
  end
end
