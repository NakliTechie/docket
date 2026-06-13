require "test_helper"

# Verifies the SigV4 signer against AWS's published "get-vanilla" test-suite
# vector, plus the documented signing-key derivation. This is the correctness
# anchor for the SES/S3 providers built on it.
class Connectors::AwsSigv4Test < ActiveSupport::TestCase
  GET_VANILLA_SIGNATURE = "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31".freeze

  test "it reproduces AWS's get-vanilla authorization vector" do
    signer = Connectors::AwsSigv4.new(
      access_key: "AKIDEXAMPLE",
      secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      region: "us-east-1", service: "service"
    )
    out = signer.sign(method: "GET", uri: URI("https://example.amazonaws.com/"),
                      payload: "", now: Time.utc(2015, 8, 30, 12, 36, 0))
    assert_equal "20150830T123600Z", out["X-Amz-Date"]
    assert_equal(
      "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, " \
      "SignedHeaders=host;x-amz-date, Signature=#{GET_VANILLA_SIGNATURE}",
      out["Authorization"]
    )
  end

  test "hashed_payload is the SHA-256 hex of the body (empty-string vector)" do
    assert_equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                 Connectors::AwsSigv4.hashed_payload("")
  end

  test "signing is deterministic for fixed inputs and time" do
    signer = Connectors::AwsSigv4.new(access_key: "AK", secret_key: "SK", region: "ap-south-1", service: "s3")
    args = { method: "PUT", uri: URI("https://b.s3.ap-south-1.amazonaws.com/k.txt"),
             payload: "hi", headers: { "x-amz-content-sha256" => Connectors::AwsSigv4.hashed_payload("hi") },
             now: Time.utc(2026, 6, 13, 9, 0, 0) }
    assert_equal signer.sign(**args), signer.sign(**args)
    assert_includes signer.sign(**args)["Authorization"], "SignedHeaders=host;x-amz-content-sha256;x-amz-date"
  end
end
