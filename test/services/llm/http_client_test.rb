require "test_helper"

class Llm::HttpClientTest < ActiveSupport::TestCase
  # A stand-in for Net::HTTP that records the read_timeout and returns a
  # canned 200 so chat() can complete without a real network call.
  class FakeResponse
    def code
      "200"
    end

    def body
      '{"choices":[{"message":{"content":"ok"}}]}'
    end
  end

  class FakeHttp
    attr_reader :read_timeout

    def use_ssl=(_value); end
    def open_timeout=(_value); end

    def read_timeout=(value)
      @read_timeout = value
    end

    def request(_req)
      FakeResponse.new
    end
  end

  # Swap Net::HTTP.new for a recorder for the duration of the block, then
  # restore it — avoids depending on minitest/mock (absent in this build).
  def with_fake_http
    fake = FakeHttp.new
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_args| fake }
    yield fake
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "chat applies the supplied interactive read_timeout (M21)" do
    with_fake_http do |http|
      Llm::HttpClient.new(endpoint: "http://model.local", model: "m")
                     .chat([ { role: "user", content: "hi" } ], read_timeout: 25)
      assert_equal 25, http.read_timeout
    end
  end

  test "chat defaults to the background read_timeout" do
    with_fake_http do |http|
      Llm::HttpClient.new(endpoint: "http://model.local", model: "m")
                     .chat([ { role: "user", content: "hi" } ])
      assert_equal Llm::HttpClient::DEFAULT_READ_TIMEOUT, http.read_timeout
    end
  end
end
