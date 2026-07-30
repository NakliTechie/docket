require "test_helper"

class Docket::OutboundUrlTest < ActiveSupport::TestCase
  def with_resolution(addresses)
    original = Docket::OutboundUrl.method(:resolve)
    Docket::OutboundUrl.define_singleton_method(:resolve) { |*_args| addresses }
    yield
  ensure
    Docket::OutboundUrl.define_singleton_method(:resolve, original)
  end

  test "vetted_address accepts a public DNS answer" do
    with_resolution([ "93.184.216.34" ]) do
      assert_equal "93.184.216.34",
                   Docket::OutboundUrl.vetted_address("hooks.example.com", port: 443)
    end
  end

  test "vetted_address rejects any blocked answer from multi-answer DNS" do
    answers = [ "93.184.216.34", "10.0.0.8" ]
    with_resolution(answers) do
      error = assert_raises(Docket::OutboundUrl::Blocked) do
        Docket::OutboundUrl.vetted_address("hooks.example.com", port: 443)
      end
      assert_includes error.message, "10.0.0.8"
    end
  end

  test "vetted_address rejects IPv4-mapped loopback" do
    with_resolution([ "::ffff:127.0.0.1" ]) do
      assert_raises(Docket::OutboundUrl::Blocked) do
        Docket::OutboundUrl.vetted_address("hooks.example.com", port: 443)
      end
    end
  end

  test "a DNS resolution failure is explicit and retryable by the caller" do
    resolver = lambda do |*_args|
      raise SocketError, "name not known"
    end
    original = Addrinfo.method(:getaddrinfo)
    Addrinfo.define_singleton_method(:getaddrinfo, resolver)
    begin
      error = assert_raises(Docket::OutboundUrl::ResolutionError) do
        Docket::OutboundUrl.vetted_address("missing.example", port: 443)
      end
      assert_includes error.message, "could not resolve"
    ensure
      Addrinfo.define_singleton_method(:getaddrinfo, original)
    end
  end
end
