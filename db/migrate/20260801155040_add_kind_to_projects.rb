class AddKindToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :kind, :integer, default: 0, null: false
    # Existing deal-linked projects were all created by DealOnboarding, so they
    # are onboarding (1). Manually-created projects stay standard (0).
    execute "UPDATE projects SET kind = 1 WHERE onboarding_deal_id IS NOT NULL"
  end

  def down
    remove_column :projects, :kind
  end
end
