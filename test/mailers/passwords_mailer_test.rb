require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset mail renders the localized subject and body (S18)" do
    user = users(:admin)
    user.update_column(:locale, "en")
    mail = PasswordsMailer.reset(user)
    assert_equal I18n.t("passwords_mailer.reset.subject", locale: :en), mail.subject
    assert_match I18n.t("passwords_mailer.reset.link_text", locale: :en), mail.html_part.body.to_s
  end

  test "reset mail honours the recipient's locale (S18)" do
    user = users(:admin)
    user.update_column(:locale, "hi")
    mail = PasswordsMailer.reset(user)
    assert_equal I18n.t("passwords_mailer.reset.subject", locale: :hi), mail.subject
    assert_match I18n.t("passwords_mailer.reset.link_text", locale: :hi), mail.html_part.body.to_s
    # The ambient locale must be restored after delivery.
    assert_equal I18n.default_locale, I18n.locale
  end

  test "an unknown recipient locale falls back to the default (S18)" do
    user = users(:admin)
    user.update_column(:locale, "zz")
    mail = PasswordsMailer.reset(user)
    assert_equal I18n.t("passwords_mailer.reset.subject", locale: I18n.default_locale), mail.subject
  end
end
