require "test_helper"

class ReferenceDocsTest < ActionDispatch::IntegrationTest
  def upload(name, content, content_type)
    file = Tempfile.new(name)
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: name)
  end

  test "a failed upload extraction blocks the save instead of reporting success (M33)" do
    sign_in_as users(:admin)
    assert_no_difference "ReferenceDoc.count" do
      post admin_reference_docs_path, params: {
        reference_doc: { title: "Bad upload", file: upload("x.zip", "PK\x03\x04 junk", "application/zip") }
      }
    end
    assert_response :unprocessable_entity # not a redirect-with-success
  end

  test "a clean text upload extracts the body and saves" do
    sign_in_as users(:admin)
    assert_difference "ReferenceDoc.count", 1 do
      post admin_reference_docs_path, params: {
        reference_doc: { title: "Good doc", file: upload("note.txt", "Pension arrears fixed in 3 days.", "text/plain") }
      }
    end
    assert_equal "Pension arrears fixed in 3 days.", ReferenceDoc.order(:id).last.body
  end
end
