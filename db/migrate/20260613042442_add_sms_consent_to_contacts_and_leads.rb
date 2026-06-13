class AddSmsConsentToContactsAndLeads < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :sms_consent, :boolean, default: false, null: false
    add_column :leads, :sms_consent, :boolean, default: false, null: false
  end
end
