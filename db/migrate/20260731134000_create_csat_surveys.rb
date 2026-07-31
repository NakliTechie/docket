class CreateCsatSurveys < ActiveRecord::Migration[8.1]
  def change
    create_table :csat_surveys do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :case, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: true, foreign_key: { on_delete: :nullify }
      t.datetime :invited_at, null: false
      t.datetime :sent_at
      t.integer :score
      t.text :comment
      t.datetime :responded_at
      t.timestamps
    end
    add_index :csat_surveys, %i[tenant_id case_id], unique: true
    add_index :csat_surveys, %i[tenant_id responded_at]
    add_check_constraint :csat_surveys, "score IS NULL OR score BETWEEN 1 AND 5",
                         name: "csat_surveys_score_valid"
  end
end
