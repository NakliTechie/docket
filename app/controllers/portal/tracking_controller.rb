module Portal
  # Status check by tracking ID + a verification challenge: the
  # supplied email or phone must match the case contact (handoff §3).
  # Stateless: every view/reply re-verifies; failures are generic to
  # prevent tracking-ID enumeration.
  class TrackingController < BaseController
    def new
    end

    def show
      @case = verified_case
      if @case
        @messages = public_thread(@case)
        render :show
      else
        flash.now[:alert] = t("portal.tracking.not_found")
        render :new, status: :unprocessable_entity
      end
    end

    def reply
      @case = verified_case
      unless @case
        flash.now[:alert] = t("portal.tracking.not_found")
        return render :new, status: :unprocessable_entity
      end

      message = @case.messages.build(
        kind: :public_reply, direction: :inbound, author: @case.contact,
        body: params[:body], files: params[:files].presence || []
      )
      if @case.status_closed?
        flash.now[:alert] = t("portal.tracking.closed_no_reply")
      elsif message.save
        flash.now[:notice] = t("portal.tracking.reply_sent")
      else
        flash.now[:alert] = message.errors.full_messages.to_sentence
      end
      @messages = public_thread(@case)
      render :show, status: flash.now[:alert] ? :unprocessable_entity : :ok
    end

    private

    def verified_case
      tracking_id = params[:tracking_id].to_s.strip.upcase
      kase = Case.find_by(tracking_id: tracking_id)
      return nil unless kase

      email = params[:contact_email].to_s.strip.downcase.presence
      phone = params[:contact_phone].to_s.gsub(/[^\d+]/, "").presence
      contact = kase.contact

      matches = (email && contact.email.present? && contact.email == email) ||
                (phone && contact.phone.present? && contact.phone == phone)
      matches ? kase : nil
    end

    # Citizens see public replies and agent turns — never internal notes.
    def public_thread(kase)
      kase.messages.where(kind: [ :public_reply, :agent_turn ])
          .with_attached_files.includes(:author).order(:created_at)
    end
  end
end
