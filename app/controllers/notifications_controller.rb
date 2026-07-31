class NotificationsController < ApplicationController
  before_action :set_notification, only: :read

  def index
    authorize Notification
    scope = policy_scope(Notification).includes(:actor, :notifiable).recent_first
    scope = scope.unread if params[:status] == "unread"
    @pagy, @notifications = pagy(scope)
  end

  def read
    authorize @notification
    @notification.mark_read!
    redirect_to destination_for(@notification), status: :see_other
  end

  def read_all
    authorize Notification
    policy_scope(Notification).unread.find_each(&:mark_read!)
    redirect_to notifications_path, notice: t(".updated"), status: :see_other
  end

  private

  def set_notification
    @notification = policy_scope(Notification).find(params[:id])
  end

  def destination_for(notification)
    record = notification.notifiable
    return notifications_path if record.nil? || !policy(record).show?

    case record
    when Case then case_path(record)
    when WorkItem then work_item_path(record)
    else notifications_path
    end
  end
end
