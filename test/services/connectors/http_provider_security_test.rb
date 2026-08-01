require "test_helper"

class Connectors::HttpProviderSecurityTest < ActiveSupport::TestCase
  class ProbeProvider < Connectors::HttpProvider
    def probe(uri) = get(uri)
  end

  class FakeHttp
    attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout
    attr_reader :requested

    def request(_request)
      @requested = true
      Struct.new(:code, :body).new("200", "{}")
    end
  end

  def with_transport(vetted: "203.0.113.10")
    fake = FakeHttp.new
    original_http = Net::HTTP.method(:new)
    original_vetted = Docket::OutboundUrl.method(:vetted_address)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    Docket::OutboundUrl.define_singleton_method(:vetted_address) { |*, **| vetted }
    yield fake
  ensure
    Net::HTTP.define_singleton_method(:new, original_http)
    Docket::OutboundUrl.define_singleton_method(:vetted_address, original_vetted)
  end

  test "pins the connection to the address vetted immediately before connect" do
    with_transport do |http|
      ProbeProvider.new(Connector.new).probe(URI("https://api.example.test/records"))

      assert_equal "203.0.113.10", http.ipaddr
      assert http.requested
    end
  end

  test "does not send credentials when final DNS resolution is blocked" do
    with_transport(vetted: nil) do |http|
      Docket::OutboundUrl.define_singleton_method(:vetted_address) do |*, **|
        raise Docket::OutboundUrl::Blocked, "resolved to metadata"
      end

      error = assert_raises(Connectors::Error) do
        ProbeProvider.new(Connector.new).probe(URI("https://api.example.test/records"))
      end
      assert_includes error.message, "blocked"
      refute http.requested
    end
  end
end
