require "test_helper"

# The background SMS send for sequence steps: delivers through Comms::SmsGateway
# only for an active, configured connector; otherwise a quiet no-op.
class SmsDeliveryJobTest < ActiveJob::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(_req) = @r
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def active_connector
    c = Connector.create!(name: "SMS", provider: "msg91", status: :active, config: { "template_id" => "T1" })
    c.credentials_hash = { "authkey" => "k" }
    c.save!
    c
  end

  test "sends through the gateway for an active configured connector" do
    c = active_connector
    with_http(200) do |reqs|
      SmsDeliveryJob.perform_now(c.id, "+919900000001", { "name" => "A" })
      assert_equal 1, reqs.size
    end
  end

  test "is a no-op for a draft connector or a missing id" do
    draft = Connector.create!(name: "Draft", provider: "msg91", status: :draft)
    draft.credentials_hash = { "authkey" => "k" }
    draft.save!
    with_http(200) do |reqs|
      SmsDeliveryJob.perform_now(draft.id, "+9100", {})
      SmsDeliveryJob.perform_now(-1, "+9100", {})
      assert_empty reqs
    end
  end
end
