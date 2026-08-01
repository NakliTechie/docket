require "test_helper"

class SprintConcurrencyGuardTest < ActiveSupport::TestCase
  test "the database permits only one live active sprint per project" do
    project = projects(:pep)
    Sprint.create!(project: project, name: "First", status: :active)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Sprint.create!(project: project, name: "Second", status: :active)
    end
    assert error.record.errors[:status].any?
  end
end
