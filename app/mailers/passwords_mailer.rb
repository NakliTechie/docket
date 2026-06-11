class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    I18n.with_locale(recipient_locale(user)) do
      mail subject: t("passwords_mailer.reset.subject"), to: user.email_address
    end
  end

  private

  def recipient_locale(user)
    available = I18n.available_locales.map(&:to_s)
    user.locale.to_s.presence_in(available) || I18n.default_locale
  end
end
