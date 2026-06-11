require "test_helper"

class ReferenceDocTest < ActiveSupport::TestCase
  test "an attached file must be an extractable type (L)" do
    doc = ReferenceDoc.new(title: "Bad attachment", body: "pasted content")
    doc.file.attach(io: StringIO.new("PK\x03\x04"), filename: "evil.zip", content_type: "application/zip")
    assert_not doc.valid?
    assert doc.errors[:file].any?
  end

  test "an extractable attachment passes validation (L)" do
    doc = ReferenceDoc.new(title: "Good attachment", body: "pasted content")
    doc.file.attach(io: StringIO.new("hello"), filename: "note.txt", content_type: "text/plain")
    assert doc.valid?
  end
end
