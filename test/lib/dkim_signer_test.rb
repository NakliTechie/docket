require "test_helper"

class DkimSignerTest < ActiveSupport::TestCase
  setup do
    @key = OpenSSL::PKey::RSA.generate(2048)
    @signer = Docket::DkimSigner.new(
      domain: "mail.example.test", selector: "docket", private_key: @key.to_pem
    )
  end

  test "signs the encoded body and headers with a verifiable relaxed RSA signature" do
    mail = Mail.new do
      from "support@mail.example.test"
      to "customer@example.test"
      subject "A folded subject for deterministic DKIM verification"
      body "Hello  world  \n\n"
    end

    @signer.sign(mail)
    field = mail["DKIM-Signature"]
    value = field.value
    signature = Base64.strict_decode64(value.split("b=", 2).last.delete(" \r\n"))
    header_names = value[/h=([^;]+)/, 1].split(":")
    unsigned_value = value.sub(/b=.*/m, "b=")
    signing_data = header_names.map { |name| @signer.relaxed_header(mail.header[name].encoded) }.join
    signing_data << @signer.relaxed_header("DKIM-Signature: #{unsigned_value}\r\n")

    assert @key.public_key.verify(OpenSSL::Digest::SHA256.new, signature, signing_data)
    body = mail.encoded.split("\r\n\r\n", 2).last
    expected_hash = Base64.strict_encode64(
      OpenSSL::Digest::SHA256.digest(@signer.relaxed_body(body))
    )
    assert_equal expected_hash, value[/bh=([^;]+)/, 1]
  end

  test "rejects partial configuration and weak key material" do
    assert_raises(Docket::DkimSigner::ConfigurationError) do
      Docket::DkimSigner.new(domain: "mail.example.test", selector: "docket",
                             private_key: OpenSSL::PKey::RSA.generate(1024).to_pem)
    end
  end
end
