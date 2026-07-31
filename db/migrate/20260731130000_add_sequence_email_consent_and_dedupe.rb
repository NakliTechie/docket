class AddSequenceEmailConsentAndDedupe < ActiveRecord::Migration[8.1]
  def change
    %i[contacts leads].each do |table|
      add_column table, :email_consent, :boolean, null: false, default: false
      add_column table, :email_unsubscribed_at, :datetime
    end

    add_index :sequence_enrollments,
              %i[tenant_id sequence_id enrollable_type enrollable_id],
              unique: true,
              where: "status = 0 AND deleted_at IS NULL",
              name: "index_sequence_enrollments_on_unique_active_target"
  end
end
