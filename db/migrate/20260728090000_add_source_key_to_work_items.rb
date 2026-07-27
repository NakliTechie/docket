class AddSourceKeyToWorkItems < ActiveRecord::Migration[8.1]
  # Where an item came from, e.g. "PEP-77" in the source Jira. THIS is the
  # import idempotency key. It used to be the trailing number, which meant
  # AAA-1, BBB-1 and CCC-1 all collapsed onto number 1 and overwrote whatever
  # already held it.
  def change
    add_column :work_items, :source_key, :string
    # Excludes tombstones for the same reason every other uniqueness rule here
    # does (the W1 class): a soft-deleted row must not reserve a key, or a
    # re-import after a delete collides with something nobody can see.
    add_index :work_items, %i[project_id source_key], unique: true,
              where: "source_key IS NOT NULL AND deleted_at IS NULL"
  end
end
