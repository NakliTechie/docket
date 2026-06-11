class MakeUsersEmailIndexSoftDeleteAware < ActiveRecord::Migration[8.1]
  # Match every other SoftDeletable model: scope the unique index to live
  # rows so a soft-deleted user's email can be re-provisioned (the model
  # validation is scoped the same way). Without this, re-creating a user
  # with a soft-deleted user's email raises RecordNotUnique at the DB.
  def change
    remove_index :users, :email_address, unique: true, name: "index_users_on_email_address"
    add_index :users, :email_address, unique: true,
              where: "deleted_at IS NULL", name: "index_users_on_email_address"
  end
end
