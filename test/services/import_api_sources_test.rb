require "test_helper"

class ImportApiSourcesTest < ActiveSupport::TestCase
  def with_vetted_address
    original = Docket::OutboundUrl.method(:vetted_address)
    Docket::OutboundUrl.define_singleton_method(:vetted_address) { |*, **| "93.184.216.34" }
    yield
  ensure
    Docket::OutboundUrl.define_singleton_method(:vetted_address, original)
  end

  test "Freshdesk paginates tickets and every ticket conversation page" do
    ticket_request = stub_request(:get, %r{https://acme\.freshdesk\.com/api/v2/tickets\?})
      .to_return(
        { status: 200, body: [ { id: 10, subject: "API ticket" } ].to_json,
          headers: { "Content-Type" => "application/json" } },
        { status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" } }
      )
    conversation_request = stub_request(
      :get, %r{https://acme\.freshdesk\.com/api/v2/tickets/10/conversations\?}
    ).to_return(
      { status: 200, body: [ { id: 20, body_text: "first page" } ].to_json,
        headers: { "Content-Type" => "application/json" } },
      { status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" } }
    )

    source = Imports::FreshdeskApi.new(domain: "acme.freshdesk.com", api_key: "secret",
                                        per_page: 1)
    with_vetted_address do
      ticket = source.each_entity("tickets").first
      assert_equal 10, ticket["id"]
      assert_equal [ 20 ], ticket["conversations"].to_a.pluck("id")
    end

    assert_requested ticket_request, times: 1 # Enumerator#first needs only page one.
    assert_requested conversation_request, times: 2
  end

  test "Freshdesk initial tickets request is complete and deterministically ordered" do
    request = stub_request(:get, "https://acme.freshdesk.com/api/v2/tickets")
      .with(query: hash_including(
        "updated_since" => "1970-01-01T00:00:00Z", "include" => /description/,
        "order_by" => "updated_at", "order_type" => "asc"
      ))
      .to_return(status: 200, body: [].to_json,
                 headers: { "Content-Type" => "application/json" })
    source = Imports::FreshdeskApi.new(domain: "acme.freshdesk.com", api_key: "secret")

    with_vetted_address { assert_empty source.each_entity("tickets").to_a }

    assert_requested request
  end

  test "Freshdesk pagination fails visibly at a provider page cap" do
    stub_request(:get, %r{https://acme\.freshdesk\.com/api/v2/companies\?})
      .to_return(status: 200, body: [ { id: 1 } ].to_json,
                 headers: { "Content-Type" => "application/json" })
    source = Imports::FreshdeskApi.new(domain: "acme.freshdesk.com", api_key: "secret",
                                       per_page: 1)

    error = assert_raises(Imports::HttpSource::Error) do
      with_vetted_address do
        source.send(:paginated, "/api/v2/companies", max_pages: 2).to_a
      end
    end
    assert_match "2-page cap", error.message
  end

  test "Jira follows search cursors and independent comment pagination" do
    search_request = stub_request(:get, %r{https://jira\.example\.com/rest/api/3/search/jql\?})
      .to_return(
        { status: 200, body: {
          issues: [ { key: "APP-1", fields: { summary: "One" } } ],
          nextPageToken: "NEXT", isLast: false
        }.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: {
          issues: [ { key: "APP-2", fields: { summary: "Two" } } ], isLast: true
        }.to_json, headers: { "Content-Type" => "application/json" } }
      )
    comment_request = stub_request(
      :get, %r{https://jira\.example\.com/rest/api/3/issue/APP-1/comment\?}
    ).to_return(
      { status: 200, body: { comments: [ { id: "C1", body: "note" } ], total: 1 }.to_json,
        headers: { "Content-Type" => "application/json" } }
    )

    source = Imports::JiraApi.new(base_url: "https://jira.example.com", email: "admin@example.test",
                                  api_token: "secret", page_size: 1)
    issues = nil
    with_vetted_address do
      issues = source.each_entity("issues").to_a
      assert_equal %w[APP-1 APP-2], issues.pluck("key")
      assert_equal [ "C1" ], issues.first.dig("fields", "comment", "comments").to_a.pluck("id")
    end

    assert_requested search_request, times: 2
    assert_requested comment_request, times: 1
  end

  test "Jira adds deterministic ordering to custom and delta JQL" do
    source = Imports::JiraApi.new(base_url: "https://jira.example.com",
                                  email: "admin@example.test", api_token: "secret",
                                  jql: "project = APP")
    source.watermark = Time.zone.parse("2026-01-02T03:04:05Z")

    query = source.send(:effective_jql)

    assert_match(/\(project = APP\) AND updated >=/, query)
    assert query.end_with?("ORDER BY updated ASC, id ASC"), query
  end

  test "credentialed migration sources reject plaintext HTTP by default" do
    error = assert_raises(Imports::HttpSource::Error) do
      Imports::JiraApi.new(base_url: "http://jira.example.com",
                           email: "admin@example.test", api_token: "secret")
    end
    assert_equal "migration source must use HTTPS", error.message

    assert_nothing_raised do
      Imports::JiraApi.new(base_url: "http://jira.example.com",
                           email: "admin@example.test", api_token: "secret",
                           allow_insecure: true)
    end
  end

  test "attachment downloads do not forward source credentials across origins" do
    request = stub_request(:get, "https://cdn.example.test/file.txt")
      .with { |req| req.headers["Authorization"].nil? }
      .to_return(status: 200, body: "history", headers: { "Content-Type" => "text/plain" })
    source = Imports::FreshdeskApi.new(domain: "acme.freshdesk.com", api_key: "secret")
    material = nil

    with_vetted_address do
      material = source.download_attachment(
        "id" => 2, "name" => "file.txt", "content_type" => "text/plain",
        "attachment_url" => "https://cdn.example.test/file.txt"
      )
    end

    assert_equal "history", material.fetch(:io).read
    assert_requested request
  ensure
    material&.fetch(:io)&.close!
  end
end
