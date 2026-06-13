require "test_helper"

class SequencesTest < ActionDispatch::IntegrationTest
  def create_sequence
    seq = Sequence.new(name: "Onboarding")
    seq.sequence_steps.build(position: 0, delay_days: 0, body: "Welcome")
    seq.save!
    seq
  end

  test "admin can create a sequence with steps" do
    sign_in_as users(:admin)
    assert_difference [ "Sequence.count", "SequenceStep.count" ], 1 do
      post sequences_path, params: { sequence: {
        name: "Drip", active: "1",
        sequence_steps_attributes: { "0" => { position: 0, delay_days: 0, body: "Hello" } }
      } }
    end
    assert_redirected_to sequence_path(Sequence.order(:id).last)
  end

  test "a sales rep can enroll a lead and cancel the enrollment" do
    seq = create_sequence
    lead = Lead.create!(name: "Enroll Me", email: "enroll@example.com")
    sign_in_as users(:sales)

    assert_difference "SequenceEnrollment.count", 1 do
      post sequence_enrollments_path, params: { sequence_id: seq.id, enrollable_type: "Lead", enrollable_id: lead.id }
    end
    enrollment = SequenceEnrollment.order(:id).last
    assert_equal lead, enrollment.enrollable

    post cancel_sequence_enrollment_path(enrollment)
    assert enrollment.reload.status_cancelled?
  end

  test "agents cannot manage sequence definitions" do
    sign_in_as users(:agent_a)
    get new_sequence_path
    assert_response :forbidden
  end

  test "sequence definitions list and show are visible to staff" do
    create_sequence
    sign_in_as users(:supervisor)
    get sequences_path
    assert_response :success
    assert_match "Onboarding", response.body
  end
end
