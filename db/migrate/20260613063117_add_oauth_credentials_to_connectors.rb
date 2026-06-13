class AddOauthCredentialsToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :oauth_credentials, :text
  end
end
