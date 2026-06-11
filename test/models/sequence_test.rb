require "test_helper"

class SequenceTest < ActiveSupport::TestCase
  def build_sequence
    seq = Sequence.new(name: "Nurture")
    seq.sequence_steps.build(position: 0, delay_days: 0, body: "Hi {{contact_name}}")
    seq.sequence_steps.build(position: 1, delay_days: 3, body: "Following up")
    seq
  end

  test "requires a name and at least one step" do
    assert_not Sequence.new(name: "Empty").valid?
    assert build_sequence.valid?
  end

  test "enroll creates an active enrollment due after the first step's delay" do
    seq = build_sequence
    seq.save!
    lead = Lead.create!(name: "Target", email: "t@example.com")
    enr = seq.enroll!(lead)
    assert enr.status_active?
    assert_equal 0, enr.current_step_position
    assert_operator enr.next_run_at, :<=, Time.current # delay_days 0
  end

  test "step interpolation fills {{vars}} and leaves unknown tokens" do
    step = SequenceStep.new(subject: "Hi {{contact_name}}", body: "From {{company_name}} — {{unknown}}")
    vars = { "contact_name" => "Asha", "company_name" => "Acme" }
    assert_equal "Hi Asha", step.render_subject(vars)
    assert_equal "From Acme — {{unknown}}", step.render_body(vars)
  end
end
