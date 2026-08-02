class AddKnowledgeLifecycle < ActiveRecord::Migration[8.1]
  class MigrationReferenceDoc < ActiveRecord::Base
    self.table_name = "reference_docs"
  end

  class MigrationReferenceDocVersion < ActiveRecord::Base
    self.table_name = "reference_doc_versions"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationKnowledgeCategory < ActiveRecord::Base
    self.table_name = "knowledge_categories"
  end

  def up
    create_table :knowledge_categories do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :knowledge_categories }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :knowledge_categories, [ :tenant_id, :slug ], unique: true,
              where: "deleted_at IS NULL"
    add_index :knowledge_categories, [ :tenant_id, :parent_id, :name ], unique: true,
              where: "deleted_at IS NULL", name: "index_knowledge_categories_on_parent_and_name"
    add_index :knowledge_categories, :deleted_at

    add_column :reference_docs, :locale, :string, null: false, default: "en"
    add_column :reference_docs, :translation_key, :string
    add_reference :reference_docs, :knowledge_category, foreign_key: true

    create_table :reference_doc_versions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :reference_doc, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :locale, null: false
      t.integer :status, null: false
      t.integer :visibility, null: false
      t.references :knowledge_category, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end
    add_index :reference_doc_versions, [ :reference_doc_id, :number ], unique: true,
              name: "index_reference_doc_versions_on_doc_and_number"

    add_reference :reference_docs, :current_version, foreign_key: { to_table: :reference_doc_versions }

    create_table :reference_doc_ratings do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :reference_doc, null: false, foreign_key: true
      t.references :reference_doc_version, null: false, foreign_key: true
      t.string :visitor_token_digest, null: false
      t.boolean :helpful, null: false
      t.timestamps
    end
    add_index :reference_doc_ratings,
              [ :reference_doc_version_id, :visitor_token_digest ],
              unique: true, name: "index_reference_doc_ratings_on_version_and_visitor"

    backfill_knowledge_lifecycle

    change_column_null :reference_docs, :translation_key, false
    add_index :reference_docs, [ :tenant_id, :translation_key, :locale ], unique: true,
              where: "deleted_at IS NULL", name: "index_reference_docs_on_translation_and_locale"
    remove_index :reference_docs, name: "index_reference_docs_on_tenant_id_and_title"
    add_index :reference_docs, [ :tenant_id, :locale, :title ], unique: true,
              where: "deleted_at IS NULL", name: "index_reference_docs_on_tenant_locale_title"
  end

  def down
    remove_index :reference_docs, name: "index_reference_docs_on_tenant_locale_title"
    add_index :reference_docs, [ :tenant_id, :title ], unique: true,
              where: "deleted_at IS NULL", name: "index_reference_docs_on_tenant_id_and_title"
    remove_index :reference_docs, name: "index_reference_docs_on_translation_and_locale"
    drop_table :reference_doc_ratings
    remove_reference :reference_docs, :current_version
    drop_table :reference_doc_versions
    remove_reference :reference_docs, :knowledge_category
    remove_column :reference_docs, :translation_key
    remove_column :reference_docs, :locale
    drop_table :knowledge_categories
  end

  private

  def backfill_knowledge_lifecycle
    category_map = {}

    MigrationReferenceDoc.reset_column_information
    MigrationReferenceDocVersion.reset_column_information
    MigrationKnowledgeCategory.reset_column_information

    MigrationReferenceDoc.find_each do |doc|
      knowledge_category_id = migrated_category_id(doc, category_map)
      translation_key = SecureRandom.uuid
      doc.update_columns(
        locale: I18n.default_locale.to_s,
        translation_key: translation_key,
        knowledge_category_id: knowledge_category_id
      )
      version = MigrationReferenceDocVersion.create!(
        tenant_id: doc.tenant_id,
        reference_doc_id: doc.id,
        number: 1,
        title: doc.title,
        body: doc.body,
        locale: I18n.default_locale.to_s,
        status: doc.status,
        visibility: doc.visibility,
        knowledge_category_id: knowledge_category_id,
        created_at: doc.updated_at
      )
      doc.update_columns(current_version_id: version.id)
    end
  end

  def migrated_category_id(doc, category_map)
    return if doc.category_id.blank?

    key = [ doc.tenant_id, doc.category_id ]
    category_map[key] ||= begin
      category = MigrationCategory.find_by(id: doc.category_id)
      if category
        base = category.name.to_s.parameterize.presence || "category-#{category.id}"
        slug = base
        suffix = 1
        while MigrationKnowledgeCategory.where(tenant_id: doc.tenant_id, slug: slug).exists?
          suffix += 1
          slug = "#{base}-#{suffix}"
        end
        MigrationKnowledgeCategory.create!(
          tenant_id: doc.tenant_id,
          name: category.name,
          slug: slug,
          description: category.try(:description)
        ).id
      end
    end
  end
end
