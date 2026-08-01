require "test_helper"

class LeadScoringTest < ActiveSupport::TestCase
  def lead(**attrs)
    Lead.create!({ name: "L", email: "l@x.example", source: :manual }.merge(attrs))
  end

  test "score persists on create from the default scorecard" do
    hot = lead(email: "h@x.example", phone: "9990001111", company_name: "Acme",
               source: :referral, owner: users(:sales))
    assert_equal 5, hot.score
    assert hot.band_hot?
  end

  test "a bare email lead is cold; email+phone+company is warm" do
    assert lead(phone: nil, company_name: nil).band_cold?
    warm = lead(phone: "9990001111", company_name: "Acme")
    assert_equal 3, warm.score
    assert warm.band_warm?
  end

  test "score recomputes when a signal changes" do
    l = lead(phone: nil, company_name: nil) # score 1 (email)
    assert_equal 1, l.score
    l.update!(phone: "9990001111", company_name: "Acme")
    assert_equal 3, l.reload.score
    assert l.band_warm?
  end

  test "a non-signal change does not thrash the score" do
    l = lead(company_name: "Acme")
    before = l.score
    l.update!(notes: "just a note")
    assert_equal before, l.reload.score
  end

  test "editing the scorecard changes future scores" do
    LeadScorecard.current.update!(weight_email: 5, warm_threshold: 5, hot_threshold: 10)
    l = lead(phone: nil, company_name: nil) # email only, now worth 5
    assert_equal 5, l.score
    assert l.band_warm?
  end

  test "editing the scorecard re-scores existing leads (no stale persisted scores)" do
    stale = lead(phone: nil, company_name: nil) # score 1
    assert_equal 1, stale.score
    card = LeadScorecard.current
    card.update!(weight_email: 10, warm_threshold: 5, hot_threshold: 20)
    LeadScoring.rescore_all!(card)
    assert_equal 10, stale.reload.score
    assert stale.band_warm?
  end

  test "apply! writes nothing when the score is unchanged" do
    card = LeadScorecard.current
    l = lead(company_name: "Acme")
    l.reload
    assert_queries_count(0) { LeadScoring.apply!(l, card) }
  end

  test "the decisioning rule flags warm+ leads using the shared scoring" do
    lead(phone: "9990001111", company_name: "Acme", status: :new) # score 3 = warm
    lead(phone: nil, company_name: nil, status: :new) # score 1 = cold
    decisions = Decisioning::Rules::LeadScore.new.evaluate
    assert_equal 1, decisions.size
    assert_match(/score 3/, decisions.first.reasoning)
  end
end
