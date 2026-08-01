# An engineering deliverable — the auditable basis a quote derives from
# (Prithvi e2e, Phase 1). An engineer drafts it on the engagement (an OPEN
# deal's project), cites the studies it summarizes, and submits it for review;
# a DISTINCT human approves it with a reasoned order (maker-checker, always on —
# a deliverable can't be approved by its own author); issuing freezes the
# content and exposes a structured scope the quote turns into priced lines.
#
# "Reports inform, never bill": scope items carry engineering scope only (no
# price, no tax, no HSN/SAC) — pricing and tax are added on the Quote.
class Deliverable < ApplicationRecord
  Error = Class.new(StandardError)

  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity
  include AttachableValidation

  humanizes_enums :status

  # The keys a scope entry may carry — engineering scope only.
  SCOPE_ITEM_KEYS = %w[description quantity unit notes].freeze
  # Content frozen once issued (the quote cites this exact basis).
  FROZEN_WHEN_ISSUED = %w[title summary scope_items].freeze

  enum :status, { draft: 0, in_review: 1, approved: 2, issued: 3 }, default: :draft, prefix: :status

  belongs_to :deal
  belongs_to :project, optional: true
  belongs_to :submitted_by, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :approved_by, -> { with_deleted }, class_name: "User", optional: true

  has_many :deliverable_studies, dependent: :destroy
  has_many :studies, through: :deliverable_studies, source: :work_item
  has_many :audit_entries, as: :auditable, dependent: nil

  has_many_attached :files

  validates :title, presence: true
  validates_same_tenant :deal, :project
  validate :scope_items_are_well_formed
  validate :issued_content_is_frozen, on: :update

  # Normalized engineering scope the quote derives priced lines from. Frozen on
  # issue; readable earlier as a preview.
  def scope_entries
    Array(scope_items).filter_map do |item|
      next unless item.is_a?(Hash)
      item.slice(*SCOPE_ITEM_KEYS).symbolize_keys
    end
  end

  private

  def scope_items_are_well_formed
    return if scope_items.blank?
    unless scope_items.is_a?(Array) && scope_items.all? { |item| item.is_a?(Hash) }
      errors.add(:scope_items, "must be a list of scope entries")
      return
    end
    scope_items.each_with_index do |item, index|
      errors.add(:scope_items, "entry #{index + 1} needs a description") if item["description"].to_s.strip.blank?
      # "Reports inform, never bill" enforced at rest, not just on read: an entry
      # may not smuggle price/tax/HSN in through an unknown key.
      unknown = item.keys.map(&:to_s) - SCOPE_ITEM_KEYS
      if unknown.any?
        errors.add(:scope_items, "entry #{index + 1} may not carry #{unknown.join(', ')} — scope is engineering-only")
      end
    end
  end

  # Once issued the deliverable is the quote's frozen basis: its content may not
  # change AND it may not leave the issued state — otherwise un-issuing would be
  # a backdoor to editing frozen content. Soft-delete uses update_columns (skips
  # validation) so tombstoning is unaffected.
  def issued_content_is_frozen
    return unless status_was == "issued"
    return unless (status_changed? && status != "issued") || (changed & FROZEN_WHEN_ISSUED).any?
    errors.add(:base, "an issued deliverable is frozen and cannot be edited")
  end
end
