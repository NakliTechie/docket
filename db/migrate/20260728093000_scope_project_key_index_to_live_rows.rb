class ScopeProjectKeyIndexToLiveRows < ActiveRecord::Migration[8.1]
  # The model validation already excluded soft-deleted rows; the INDEX did not,
  # so re-creating a project with a deleted project's key passed validation and
  # then blew up with a RecordNotUnique at the database. The two must agree.
  def change
    remove_index :projects, %i[tenant_id key]
    add_index :projects, %i[tenant_id key], unique: true,
              where: "deleted_at IS NULL",
              name: "index_projects_on_tenant_id_and_key"
  end
end
