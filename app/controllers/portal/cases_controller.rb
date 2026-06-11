module Portal
  class CasesController < BaseController
    # Anonymous grievance/request form (handoff §3): no login, returns a
    # tracking ID. The confirmation is rendered (not redirected) so the
    # tracking ID never appears in a URL, log line, or Referer header.
    def new
      @submission = PortalSubmission.new
    end

    def create
      @submission = PortalSubmission.new(submission_params)
      if (kase = @submission.save)
        CaseMailer.confirmation(kase).deliver_later if kase.contact.email.present?
        render :confirmation, locals: { kase: kase }, status: :created
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def submission_params
      permitted = params.require(:portal_submission)
                        .permit(:name, :email, :phone, :subject, :description, files: [])
                        .merge(preferred_language: I18n.locale.to_s)
      permitted[:files] = safe_files(permitted[:files]) if permitted.key?(:files)
      permitted
    end
  end
end
