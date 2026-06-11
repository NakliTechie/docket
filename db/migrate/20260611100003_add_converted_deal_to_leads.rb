class AddConvertedDealToLeads < ActiveRecord::Migration[8.1]
  def change
    add_reference :leads, :converted_deal, foreign_key: { to_table: :deals }
  end
end
