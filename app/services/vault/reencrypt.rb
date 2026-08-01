module Vault
  class Reencrypt
    Result = Data.define(:records, :attributes, :errors)

    def self.call(...) = new(...).call

    def initialize(dry_run: false)
      @dry_run = dry_run
    end

    def call
      records = 0
      attributes = 0
      errors = []

      ActsAsTenant.without_tenant do
        encrypted_models.each do |model|
          relation_for(model).find_each do |record|
            encrypted = record.class.encrypted_attributes.count { |attribute| record.public_send(attribute).present? }
            next if encrypted.zero?

            record.encrypt unless @dry_run
            records += 1
            attributes += encrypted
          rescue ActiveRecord::Encryption::Errors::Decryption, ActiveRecord::ActiveRecordError => e
            errors << { model: model.name, id: record.id, error: e.message }
          end
        end
      end

      Result.new(records: records, attributes: attributes, errors: errors)
    end

    private

    def encrypted_models
      Rails.application.eager_load!
      ApplicationRecord.descendants.select { |model| model.encrypted_attributes.present? }
                       .sort_by(&:name)
    end

    def relation_for(model)
      model.respond_to?(:with_deleted) ? model.with_deleted : model.all
    end
  end
end
