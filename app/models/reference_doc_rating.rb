class ReferenceDocRating < ApplicationRecord
  acts_as_tenant(:tenant)

  belongs_to :reference_doc
  belongs_to :reference_doc_version

  validates :visitor_token_digest, presence: true,
            uniqueness: { scope: :reference_doc_version_id }
  validates :helpful, inclusion: { in: [ true, false ] }
  validate :version_belongs_to_article
  validates_same_tenant :reference_doc, :reference_doc_version

  private

  def version_belongs_to_article
    return if reference_doc.blank? || reference_doc_version.blank?
    return if reference_doc_version.reference_doc_id == reference_doc_id

    errors.add(:reference_doc_version, :invalid)
  end
end
