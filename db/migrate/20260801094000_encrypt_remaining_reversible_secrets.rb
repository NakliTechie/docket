class EncryptRemainingReversibleSecrets < ActiveRecord::Migration[8.0]
  def up
    say_with_time "encrypting setting values" do
      Setting.reset_column_information
      Setting.find_each { |record| record.update_columns(value: record.value) }
    end
    say_with_time "encrypting webhook endpoint secrets" do
      WebhookEndpoint.reset_column_information
      WebhookEndpoint.with_deleted.find_each { |record| record.update_columns(secret: record.secret) }
    end
    say_with_time "encrypting connector webhook secrets" do
      Connector.reset_column_information
      Connector.with_deleted.find_each { |record| record.update_columns(webhook_secret: record.webhook_secret) }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "encrypted secret values must not be written back as plaintext"
  end
end
