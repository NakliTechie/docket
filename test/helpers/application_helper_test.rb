require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "recording reference renders only validated http links" do
    link = recording_reference_link("https://voice.example.test/recording/1")
    assert_includes link, "https://voice.example.test/recording/1"
    assert_includes link, "rel=\"noopener noreferrer\""

    assert_nil recording_reference_link("javascript:alert(1)")
    assert_nil recording_reference_link("https://user:secret@voice.example.test/recording/1")
  end
end
