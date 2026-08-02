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
  # only published + public reach the customer portal. Internal+published is the
  # private knowledge base (grounds the agent, invisible to customers).
  enum :status, { draft: 0, published: 1, retired: 2 }, default: :published, prefix: :status
  # `public` collides with Module#public, so the enum predicates are prefixed.
  enum :visibility, { internal: 0, public: 1 }, default: :internal, prefix: :visibility

  belongs_to :category, -> { with_deleted }, optional: true
  belongs_to :knowledge_category, -> { with_deleted }, optional: true
  belongs_to :current_version, class_name: "ReferenceDocVersion", optional: true
  has_many :reference_doc_versions, -> { order(number: :desc) }, dependent: nil
  has_many :reference_doc_ratings, dependent: nil
  has_one_attached :file

  validates :title, presence: true,
            uniqueness: { scope: %i[tenant_id locale], conditions: -> { where(deleted_at: nil) } }
  validates :body, presence: true
  validates :locale, presence: true, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
  validates :translation_key, presence: true,
            uniqueness: { scope: %i[tenant_id locale], conditions: -> { where(deleted_at: nil) } }
  validates :slug, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }, allow_blank: true
  validates_same_tenant :category, :knowledge_category, :current_version
  validate :current_version_belongs_to_article
  # The attached original is only ever a source for extraction — hold it to
  # the same allowlist as every other upload surface, not "any file".
  validate :file_is_extractable

  before_validation :normalize_locale, :assign_translation_key, :assign_slug
  after_create :record_version!
  after_update :record_version!, if: :versioned_fields_changed?

  # Grounds the AI (both visibilities). Drafts never ground.
  def self.grounding(locale = I18n.locale)
    preferred_locale_variants(status_published, locale)
  end

  # The customer-facing knowledge base. A tenant's configured locale wins;
  # untranslated articles fall back to the application's default locale.
  def self.public_kb(locale = I18n.locale)
    preferred_locale_variants(status_published.visibility_public, locale).order(:title)
  end

  def self.preferred_locale_variants(scope, locale)
    requested = locale.to_s
    fallback = I18n.default_locale.to_s
    requested_variants = scope.where(locale: requested)
    return requested_variants if requested == fallback

    fallback_variants = scope.where(locale: fallback)
                             .where.not(translation_key: requested_variants.select(:translation_key))
    where(id: requested_variants.select(:id)).or(where(id: fallback_variants.select(:id)))
  end

  def translations
    self.class.where(translation_key: translation_key).where.not(id: id).order(:locale)
  end

  def version_number = current_version&.number || 0

  def helpfulness_summary
    scope = current_version ? reference_doc_ratings.where(reference_doc_version: current_version) : reference_doc_ratings.none
    helpful = scope.where(helpful: true).count
    unhelpful = scope.where(helpful: false).count
    total = helpful + unhelpful
    { helpful: helpful, unhelpful: unhelpful, total: total,
      score: total.zero? ? nil : ((helpful.to_f / total) * 100).round }
  end

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

  VERSIONED_FIELDS = %w[title body locale status visibility knowledge_category_id].freeze

  def normalize_locale
    self.locale = locale.to_s.downcase.presence || I18n.default_locale.to_s
  end

  def assign_translation_key
    self.translation_key ||= SecureRandom.uuid
  end

  def versioned_fields_changed?
    (saved_changes.keys & VERSIONED_FIELDS).any?
  end

  def record_version!
    number = reference_doc_versions.maximum(:number).to_i + 1
    actor = Current.effective_actor
    version = reference_doc_versions.create!(
      tenant: tenant,
      number: number,
      title: title,
      body: body,
      locale: locale,
      status: status,
      visibility: visibility,
      knowledge_category: knowledge_category,
      created_by: actor.is_a?(User) ? actor : nil,
      created_at: Time.current
    )
    update_column(:current_version_id, version.id)
    association(:current_version).reset
  end

  def current_version_belongs_to_article
    return if current_version.blank? || current_version.reference_doc_id == id

    errors.add(:current_version, :invalid)
  end

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
