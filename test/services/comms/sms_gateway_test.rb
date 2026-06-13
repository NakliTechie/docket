require "test_helper"

# The shared SMS sender. Reused by the agent effector and marketing sequences;
# both reach MSG91's DLT flow API through here. HTTP is stubbed at Net::HTTP.
class Comms::SmsGatewayTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def sms_connector(status: :active)
    conn = Connector.create!(name: "SMS", provider: "msg91", status: status,
      config: { "template_id" => "T1", "sender_id" => "DKT" })
    conn.credentials_hash = { "authkey" => "k" }
    conn.save!
    conn
  end

  test "deliver posts the DLT template + variables with the authkey header" do
    with_http(200, '{"type":"success"}') do |reqs|
      res = Comms::SmsGateway.new(sms_connector).deliver(mobile: "+919900000001", variables: { "name" => "Asha" })
      assert res["ok"]
      req = reqs.last.last
      assert_equal "k", req["authkey"]
      body = JSON.parse(req.body)
      assert_equal "T1", body["template_id"]
      assert_equal "Asha", body["recipients"].first["name"]
    end
  end

  test "deliver raises on a blank mobile or a missing template" do
    assert_raises(Comms::SmsGateway::Error) { Comms::SmsGateway.new(sms_connector).deliver(mobile: " ") }

    bare = Connector.create!(name: "No template", provider: "msg91", status: :active)
    bare.credentials_hash = { "authkey" => "k" }
    bare.save!
    assert_raises(Comms::SmsGateway::Error) { Comms::SmsGateway.new(bare).deliver(mobile: "+910000000000") }
  end

  test "default_connector resolves the active, configured msg91 connector" do
    Connector.where(provider: "msg91").delete_all
    assert_nil Comms::SmsGateway.default_connector
    assert_not Comms::SmsGateway.available?

    sms_connector(status: :draft) # wired but not live — excluded
    assert_nil Comms::SmsGateway.default_connector

    live = sms_connector
    assert_equal live, Comms::SmsGateway.default_connector
    assert Comms::SmsGateway.available?
  end
end
