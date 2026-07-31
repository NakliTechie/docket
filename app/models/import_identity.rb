class ImportIdentity < ApplicationRecord
  acts_as_tenant(:tenant)

  belongs_to :target, polymorphic: true, optional: true
  belongs_to :last_seen_run, class_name: "ImportRun", optional: true,
             inverse_of: :import_identities
  has_many :import_conflicts, dependent: :nullify

  validates :source, :source_instance, :source_type, :external_id, presence: true
  validates :external_id,
            uniqueness: { scope: %i[tenant_id source source_instance source_type] }

  scope :for_source, ->(source, instance = "default") {
    where(source: source.to_s, source_instance: instance.to_s)
  }

  def self.canonicalize(value)
    case value
    when Hash
      value.sort_by { |key, _| key.to_s }.to_h do |key, nested|
        [ key.to_s, canonicalize(nested) ]
      end
    when Array then value.map { |nested| canonicalize(nested) }
    else value
    end
  end
end
