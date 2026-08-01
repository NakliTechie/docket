class CreatePriceBooks < ActiveRecord::Migration[8.1]
  def change
    # PG11 — price books (CPQ on-ramp). A book lists per-product, per-currency
    # unit prices; a deal picks a book and its line items resolve through it,
    # falling back to the product's default price. One default book per tenant
    # preserves today's single-price behaviour.
    create_table :price_books do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :price_books, %i[tenant_id name], unique: true, where: "deleted_at IS NULL"
    add_index :price_books, :tenant_id, unique: true, where: "is_default AND deleted_at IS NULL",
              name: "index_price_books_one_default"

    create_table :price_book_entries do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :price_book, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.string :currency, null: false
      t.bigint :unit_price_cents, null: false
      t.timestamps
    end
    add_index :price_book_entries, %i[price_book_id product_id currency], unique: true,
              name: "index_price_book_entries_uniqueness"

    add_reference :deals, :price_book, null: true, foreign_key: { on_delete: :nullify }
  end
end
