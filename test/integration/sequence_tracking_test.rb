require "test_helper"

class SequenceTrackingTest < ActionDispatch::IntegrationTest
  setup do
    sequence = Sequence.new(name: "Tracked")
    sequence.sequence_steps.build(position: 0, delay_days: 0, subject: "Offer",
                                  body: "View https://example.test/offers/today.")
    sequence.save!
    lead = Lead.create!(name: "Tracked Lead", email: "tracked@example.com", email_consent: true)
    enrollment = sequence.enroll!(lead)
    enrollment.advance!
    @delivery = enrollment.sequence_deliveries.first
    @delivery.update!(status: :delivered, delivered_at: Time.current)
    @sequence = sequence
  end

  test "open pixel records total and unique opens without caching" do
    2.times do
      get URI.parse(SequenceTracking.open_url(@delivery)).request_uri
      assert_response :success
      assert_equal "image/gif", response.media_type
      assert_includes response.headers["Cache-Control"], "no-cache"
    end

    assert_equal 2, @delivery.reload.open_count
    assert @delivery.opened_at.present?
    assert_equal 1, @sequence.delivery_analytics.fetch(:opened)
  end

  test "signed click redirects and records total and unique clicks" do
    destination = "https://example.test/offers/today"
    path = URI.parse(SequenceTracking.click_url(@delivery, destination)).request_uri

    get path

    assert_redirected_to destination
    assert_equal 1, @delivery.reload.click_count
    assert @delivery.clicked_at.present?
    assert_equal 100.0, @sequence.delivery_analytics.fetch(:click_rate)
  end

  test "tampered click token is rejected without recording engagement" do
    get sequence_tracking_click_path(token: @delivery.tracking_token, destination: "tampered")

    assert_response :not_found
    assert_equal 0, @delivery.reload.click_count
  end
end
