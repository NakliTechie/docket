# Admin-uploaded grounding corpus (handoff §4): text/markdown pasted
# directly or extracted from an uploaded PDF/text file. The AI retrieves
# over +body+; the original file stays attached for reference.
class ReferenceDoc < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  EXTRACTABLE_TYPES = %w[application/pdf text/plain text/markdown text/csv].freeze
  MAX_EXTRACT_BYTES = 20.megabytes

  # Article lifecycle (PG3). Only published docs ground the AI or show anywhere;
  # only published + public reach the citizen portal. Internal+published is the
  # private knowledge base (grounds the agent, invisible to citizens).
  enum :status, { draft: 0, published: 1 }, default: :published, prefix: :status
  # `public` collides with Module#public, so the enum predicates are prefixed.
  enum :visibility, { internal: 0, public: 1 }, default: :internal, prefix: :visibility

  belongs_to :category, -> { with_deleted }, optional: true
  has_one_attached :file

  validates :title, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :body, presence: true
  validates :slug, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }, allow_blank: true
  # The attached original is only ever a source for extraction — hold it to
  # the same allowlist as every other upload surface, not "any file".
  validate :file_is_extractable

  before_validation :assign_slug

  # Grounds the AI (both visibilities). Drafts never ground.
  scope :grounding, -> { status_published }
  # The citizen-facing knowledge base.
  scope :public_kb, -> { status_published.visibility_public.order(:title) }

  def file_is_extractable
    return unless file.attached?
    return if EXTRACTABLE_TYPES.include?(file.content_type)
    errors.add(:file, :unsupported_type)
  end

  def self.extract_text(uploaded_file)
    return nil if uploaded_file.blank?
    raise ArgumentError, "file too large" if uploaded_file.size > MAX_EXTRACT_BYTES

    case uploaded_file.content_type
    when "application/pdf"
      reader = PDF::Reader.new(uploaded_file.tempfile.path)
      reader.pages.map(&:text).join("\n\n").squeeze("\n").strip
    when "text/plain", "text/markdown", "text/csv"
      uploaded_file.read.force_encoding("UTF-8").scrub.strip
    else
      raise ArgumentError, "unsupported file type #{uploaded_file.content_type}"
    end
  end

  private

  # A stable, unique-per-tenant URL slug derived from the title. Keeps the
  # current slug if the title is unchanged; suffixes -2, -3… on collision.
  def assign_slug
    return if slug.present? && !will_save_change_to_title?
    base = title.to_s.parameterize.presence || "article"
    candidate = base
    n = 1
    while self.class.where(slug: candidate).where.not(id: id).exists?
      n += 1
      candidate = "#{base}-#{n}"
    end
    self.slug = candidate
  end
end
