require "test_helper"

class CsatSurveyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup { Setting.set("csat_enabled", true) }
  teardown { Setting.unset("csat_enabled") }

  test "resolving a case creates one invitation and queues it once" do
    kase = cases(:pension_case)
    assert_enqueued_with(job: CsatInvitationJob) do
      kase.transition_to!(:in_progress) if kase.status_new?
      kase.transition_to!(:resolved)
    end
    survey = kase.reload.csat_survey
    assert_equal kase.contact, survey.contact

    assert_no_enqueued_jobs only: CsatInvitationJob do
      CsatSurvey.invite!(kase)
    end
    assert_equal 1, CsatSurvey.where(case: kase).count
  end

  test "the delivery job sends once and stamps the survey" do
    survey = CsatSurvey.create!(case: cases(:pension_case), contact: contacts(:asha),
                                invited_at: Time.current)
    assert_emails(1) { CsatInvitationJob.perform_now(survey) }
    assert survey.reload.sent_at?
    assert_emails(0) { CsatInvitationJob.perform_now(survey) }
  end

  test "a response is write-once" do
    survey = CsatSurvey.create!(case: cases(:pension_case), contact: contacts(:asha),
                                invited_at: Time.current)
    survey.respond!(score: 5, comment: "Excellent")
    survey.respond!(score: 1, comment: "Changed")
    assert_equal 5, survey.reload.score
    assert_equal "Excellent", survey.comment
  end

  test "no SMTP leaves a truthful unavailable invitation state" do
    survey = CsatSurvey.create!(case: cases(:pension_case), contact: contacts(:asha),
                                invited_at: Time.current)
    original = Rails.application.config.x.outbound_mail_available
    Rails.application.config.x.outbound_mail_available = false

    assert_no_emails { CsatInvitationJob.perform_now(survey) }

    assert survey.reload.delivery_unavailable?
    assert_nil survey.sent_at
  ensure
    Rails.application.config.x.outbound_mail_available = original
  end
end
