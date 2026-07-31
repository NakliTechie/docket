require "test_helper"

class ImportJsonRowsTest < ActiveSupport::TestCase
  test "streams a named array with nested strings and structures" do
    json = {
      "metadata" => { "tickets" => [ { "wrong" => true } ] },
      "tickets" => [
        { "id" => 1, "body" => "comma, brace } and quote \"" },
        { "id" => 2, "nested" => { "list" => [ 1, 2, 3 ] } }
      ]
    }.to_json

    Tempfile.create([ "docket-import", ".json" ]) do |file|
      file.write(json)
      file.flush
      rows = Imports::JsonRows.from_file(file.path, root: "tickets").to_a
      assert_equal [ 1, 2 ], rows.pluck("id")
      assert_equal [ 1, 2, 3 ], rows.second.dig("nested", "list")
    end
  end

  test "rejects a missing root instead of silently importing nothing" do
    Tempfile.create([ "docket-import", ".json" ]) do |file|
      file.write({ "contacts" => [] }.to_json)
      file.flush
      error = assert_raises(Imports::JsonRows::FormatError) do
        Imports::JsonRows.from_file(file.path, root: "tickets").to_a
      end
      assert_match(/could not find array/, error.message)
    end
  end
end
