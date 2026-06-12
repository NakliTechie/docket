require "test_helper"

# Slice A: the LLM client's tool-use turn. The loop itself lives in
# Connectors::AgentRunner; here we only verify the client returns the raw
# assistant message (with any tool_calls) and the fake drives a loop.
class Llm::ToolUseTest < ActiveSupport::TestCase
  OPENAI_TOOL = {
    type: "function",
    function: { name: "conn_1__post_json", description: "POST JSON", parameters: { "type" => "object" } }
  }.freeze

  # --- HttpClient (network stubbed) ---
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(response) = @response = response
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @response)
  end
  def with_http(response)
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(response).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def client
    Llm::HttpClient.new(endpoint: "https://llm.example.test/v1", model: "gpt-4o-mini", api_key: "k")
  end

  test "chat_with_tools returns the assistant message carrying tool_calls" do
    body = { "choices" => [ { "message" => {
      "role" => "assistant", "content" => nil,
      "tool_calls" => [ { "id" => "c1", "type" => "function",
        "function" => { "name" => "conn_1__post_json", "arguments" => "{\"body\":{}}" } } ]
    } } ] }
    msg = with_http(FakeResponse.new("200", JSON.generate(body))) do |reqs|
      m = client.chat_with_tools([ { role: "user", content: "hi" } ], tools: [ OPENAI_TOOL ])
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "auto", sent["tool_choice"]
      assert_equal "conn_1__post_json", sent.dig("tools", 0, "function", "name")
      m
    end
    assert_equal "conn_1__post_json", msg.dig("tool_calls", 0, "function", "name")
  end

  test "chat_with_tools returns a plain assistant message when the model is done" do
    body = { "choices" => [ { "message" => { "role" => "assistant", "content" => "All done." } } ] }
    msg = with_http(FakeResponse.new("200", JSON.generate(body))) do
      client.chat_with_tools([ { role: "user", content: "hi" } ], tools: [ OPENAI_TOOL ])
    end
    assert_equal "All done.", msg["content"]
    assert_nil msg["tool_calls"]
  end

  # --- FakeClient drives the loop deterministically ---

  test "fake calls the first tool, then stops once a tool result is present" do
    fake = Llm::FakeClient.new
    first = fake.chat_with_tools([ { role: "user", content: "act" } ], tools: [ OPENAI_TOOL ])
    assert_equal "conn_1__post_json", first.dig("tool_calls", 0, "function", "name")

    after = fake.chat_with_tools(
      [ { role: "user", content: "act" }, first, { role: "tool", tool_call_id: "call_1", content: "{}" } ],
      tools: [ OPENAI_TOOL ]
    )
    assert_nil after["tool_calls"]
    assert after["content"].present?
  end

  test "fake finalizes immediately when no tools are offered" do
    msg = Llm::FakeClient.new.chat_with_tools([ { role: "user", content: "x" } ], tools: [])
    assert_nil msg["tool_calls"]
    assert msg["content"].present?
  end
end
