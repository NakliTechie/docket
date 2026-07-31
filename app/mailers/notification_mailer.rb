class NotificationMailer < ApplicationMailer
  def alert(notification)
    @notification = notification
    @user = notification.user
    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      mail to: @user.email_address, subject: notification.localized_title
    end
  end
end
