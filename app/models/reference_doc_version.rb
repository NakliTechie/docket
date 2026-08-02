class ReferenceDocVersion < ApplicationRecord
  acts_as_tenant(:tenant)

  enum :status, { draft: 0, published: 1, retired: 2 }, prefix: :status
  enum :visibility, { internal: 0, public: 1 }, prefix: :visibility

  belongs_to :reference_doc
  belongs_to :knowledge_category, -> { with_deleted }, optional: true
  belongs_to :created_by, -> { with_deleted }, class_name: "User", optional: true
  has_many :reference_doc_ratings, dependent: :restrict_with_error

  validates :number, numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :reference_doc_id }
  validates :title, :body, :locale, presence: true
  validates_same_tenant :reference_doc, :knowledge_category, :created_by

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }

  def readonly? = persisted?
end
