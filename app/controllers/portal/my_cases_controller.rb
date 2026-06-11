module Portal
  # The signed-in customer's own cases: full list, thread view, filing
  # pre-attributed cases, replies — no tracking-ID dance (handoff §3).
  class MyCasesController < BaseController
    before_action :require_customer

    def index
      @pagy, @cases = pagy(current_contact.cases.order(created_at: :desc))
    end

    def show
      @case = current_contact.cases.find(params[:id])
      @messages = @case.messages.where(kind: [ :public_reply, :agent_turn ])
                       .with_attached_files.includes(:author).order(:created_at)
    end

    def new
      @case = Case.new
    end

    def create
      @case = Case.new(
        subject: params.dig(:case, :subject),
        contact: current_contact,
        channel: :web_portal,
        # Apply the default queue like every other intake surface (M10).
        queue_id: Setting.get("default_queue_id")
      )
      body = params.dig(:case, :description).to_s
      if body.blank?
        @case.errors.add(:base, t("portal.my_cases.description_required"))
        return render :new, status: :unprocessable_entity
      end

      # Case + initial message are created together: if a file is rejected
      # (disallowed type / oversize), the message raises RecordInvalid and
      # the whole thing rolls back, so we never persist an orphaned case or
      # 500 the citizen (H7).
      Case.transaction do
        @case.save!
        @case.messages.create!(kind: :public_reply, direction: :inbound,
                               author: current_contact, body: body,
                               files: safe_files(params.dig(:case, :files)))
      end
      redirect_to portal_my_case_path(@case), notice: t("portal.my_cases.created", tracking_id: @case.tracking_id)
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.each { |err| @case.errors.add(:base, err.full_message) } unless e.record == @case
      render :new, status: :unprocessable_entity
    end

    def reply
      @case = current_contact.cases.find(params[:id])
      if @case.status_closed?
        return redirect_to portal_my_case_path(@case), alert: t("portal.tracking.closed_no_reply")
      end
      message = @case.messages.build(kind: :public_reply, direction: :inbound,
                                     author: current_contact, body: params[:body],
                                     files: safe_files(params[:files]))
      if message.save
        redirect_to portal_my_case_path(@case), notice: t("portal.tracking.reply_sent")
      else
        redirect_to portal_my_case_path(@case), alert: message.errors.full_messages.to_sentence
      end
    end

    private

    def current_contact
      @current_contact ||= Contact.find_by(id: session[:portal_contact_id])
    end

    def require_customer
      redirect_to portal_root_path, alert: t("portal.customer.sign_in_required") if current_contact.nil?
    end
  end
end
