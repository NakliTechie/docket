require "test_helper"

# The W1 class: a soft-deleted row must not reserve a value nobody can see —
# EXCEPT where the reservation is the point. This test pins which is which, so
# the next uniqueness rule added to a SoftDeletable model has to make the choice
# consciously rather than inherit whichever default the author happened to type.
class SoftDeleteUniquenessTest < ActiveSupport::TestCase
  # Identifiers handed out to someone who may still hold them. Never reissued.
  DELIBERATELY_RESERVED = {
    "Case" => :tracking_id,          # a customer quotes this back at you
    "ServiceAccount" => :client_id,  # a credential resolves through it
    "Message" => :external_message_id # a provider retry must never replay a deleted delivery
  }.freeze

  def soft_deletable_models
    Rails.application.eager_load!
    ApplicationRecord.descendants.select { |m| m.include?(SoftDeletable) && m.table_exists? }
  end

  test "every uniqueness rule on a soft-deletable model is either live-scoped or deliberately reserved" do
    unguarded = soft_deletable_models.flat_map do |model|
      model.validators.grep(ActiveRecord::Validations::UniquenessValidator).flat_map do |validator|
        next [] if validator.options[:conditions].present?

        validator.attributes.map { |attribute| [ model.name, attribute ] }
      end
    end

    unexpected = unguarded.reject { |name, attribute| DELIBERATELY_RESERVED[name] == attribute }
    assert_empty unexpected,
                 "these reserve a value a soft-deleted row still holds. Either add " \
                 "conditions: -> { where(deleted_at: nil) }, or add them to " \
                 "DELIBERATELY_RESERVED with a comment saying why: #{unexpected.inspect}"
  end

  test "a soft-deleted board column does not reserve its name" do
    project = projects(:pep)
    column = project.workflow_states.create!(name: "Temp", category: :todo, position: 9)
    column.destroy

    assert project.workflow_states.create(name: "Temp", category: :todo, position: 9).persisted?,
           "a name nobody can see must not block a new column"
  end

  test "a soft-deleted project does not reserve its key" do
    project = Project.create!(key: "GONE", name: "Gone")
    project.destroy

    assert Project.create(key: "GONE", name: "Reborn").persisted?
  end

  test "a soft-deleted case DOES keep its tracking id" do
    kase = cases(:pension_case)
    tracking_id = kase.tracking_id
    kase.destroy

    duplicate = Case.new(tracking_id: tracking_id, subject: "impostor",
                         contact: contacts(:asha))
    refute duplicate.valid?, "a customer holding this ID must never be shown a different case"
  end

  # The validation and the INDEX must agree. A live-scoped validation over a
  # tombstone-counting index passes validation and then raises RecordNotUnique
  # at the database — which is how this was found.
  test "a live-scoped uniqueness validation is backed by a live-scoped index" do
    disagreements = soft_deletable_models.flat_map do |model|
      indexes = ActiveRecord::Base.connection.indexes(model.table_name)
                                  .select(&:unique)
                                  .reject { |i| i.where.to_s.include?("deleted_at") }
      model.validators.grep(ActiveRecord::Validations::UniquenessValidator).flat_map do |validator|
        next [] if validator.options[:conditions].blank?

        validator.attributes.filter_map do |attribute|
          clash = indexes.find { |i| i.columns.include?(attribute.to_s) }
          "#{model.name}.#{attribute} (index #{clash.name})" if clash
        end
      end
    end

    assert_empty disagreements,
                 "the validation excludes soft-deleted rows but the index does not, so a " \
                 "valid record raises RecordNotUnique: #{disagreements.inspect}"
  end
end
