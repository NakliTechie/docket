# M5 (forward pass 2026-06-13): SequenceEnrollment tracked its place by an index
# counter (current_step_position) into the sequence's ordered steps. Deleting a
# step mid-flight shifts every later index, so an in-flight enrollment sends the
# wrong step or skips one. Add a STABLE pointer (current_step_id) to the next
# step to deliver — deleting an earlier step no longer shifts it. The position
# counter is kept as a display-only "steps delivered" indicator. on_delete:
# nullify so deleting the exact current step ends the run cleanly (never sends a
# wrong step).
class TrackSequenceEnrollmentCurrentStep < ActiveRecord::Migration[8.1]
  def up
    add_reference :sequence_enrollments, :current_step, null: true,
                  foreign_key: { to_table: :sequence_steps, on_delete: :nullify }

    say_with_time "backfilling current_step_id from current_step_position" do
      SequenceEnrollment.reset_column_information
      ActsAsTenant.without_tenant do
        SequenceEnrollment.where(status: 0).find_each do |enr|
          step = enr.sequence&.ordered_steps&.[](enr.current_step_position)
          enr.update_columns(current_step_id: step.id) if step
        end
      end
    end
  end

  def down
    remove_reference :sequence_enrollments, :current_step
  end
end
