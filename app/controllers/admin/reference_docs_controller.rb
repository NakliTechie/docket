module Admin
  class ReferenceDocsController < ApplicationController
    require_feature "service_desk.kb"
    before_action :set_doc, only: %i[show edit update destroy toggle_published retire]

    def index
      authorize ReferenceDoc
      @reference_docs = policy_scope(ReferenceDoc).order(:title)
    end

    def new
      source = ReferenceDoc.find_by(id: params[:translation_of])
      @reference_doc = if source
        ReferenceDoc.new(translation_key: source.translation_key,
                         knowledge_category: source.knowledge_category,
                         visibility: source.visibility, status: :draft)
      else
        ReferenceDoc.new(status: :draft)
      end
      authorize @reference_doc
    end

    def show
      authorize @reference_doc
      @versions = @reference_doc.reference_doc_versions.includes(:created_by, :knowledge_category)
      @translations = @reference_doc.translations
      @helpfulness = @reference_doc.helpfulness_summary
    end

    def create
      attributes = doc_params
      attributes[:status] ||= "draft"
      @reference_doc = ReferenceDoc.new(attributes)
      authorize @reference_doc, create_policy_query
      extract_body_from_upload
      # errors.empty? first: save re-runs validations and clears the errors
      # extract_body_from_upload added, so a failed extraction would
      # otherwise be wiped and report success (M33).
      if @reference_doc.errors.empty? && @reference_doc.save
        redirect_to admin_reference_docs_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @reference_doc
    end

    def update
      @reference_doc.assign_attributes(doc_params)
      authorize @reference_doc, update_policy_query
      extract_body_from_upload
      if @reference_doc.errors.empty? && @reference_doc.save
        redirect_to admin_reference_docs_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @reference_doc
      @reference_doc.destroy
      redirect_to admin_reference_docs_path, notice: t(".deleted"), status: :see_other
    end

    # One-click publish/unpublish from the index (lifecycle without a full edit).
    def toggle_published
      authorize @reference_doc, :publish?
      @reference_doc.status_published? ? @reference_doc.status_draft! : @reference_doc.status_published!
      redirect_to admin_reference_docs_path,
                  notice: t(@reference_doc.status_published? ? ".published" : ".unpublished", title: @reference_doc.title)
    end

    def retire
      authorize @reference_doc, :retire?
      @reference_doc.status_retired!
      redirect_to admin_reference_doc_path(@reference_doc), notice: t(".retired", title: @reference_doc.title)
    end

    private

    def set_doc
      @reference_doc = ReferenceDoc.find(params[:id])
    end

    def doc_params
      params.require(:reference_doc).permit(
        :title, :body, :file, :status, :visibility, :locale, :translation_key,
        :knowledge_category_id, :category_id
      )
    end

    def update_policy_query
      return :publish? if @reference_doc.status_published?
      return :review? if @reference_doc.status_under_review?
      return :retire? if @reference_doc.status_retired?

      :update?
    end

    def create_policy_query
      return :publish? if @reference_doc.status_published?
      return :review? if @reference_doc.status_under_review?
      return :retire? if @reference_doc.status_retired?

      :create?
    end

    def extract_body_from_upload
      upload = params.dig(:reference_doc, :file)
      return if upload.blank?
      extracted = ReferenceDoc.extract_text(upload)
      @reference_doc.body = extracted if extracted.present?
    rescue ArgumentError => e
      @reference_doc.errors.add(:file, e.message)
    rescue PDF::Reader::MalformedPDFError
      @reference_doc.errors.add(:file, t("admin.reference_docs.errors.bad_pdf"))
    rescue StandardError
      # Encrypted PDFs, unsupported features, decode errors etc. surface as
      # a friendly validation error rather than 500ing the form.
      @reference_doc.errors.add(:file, t("admin.reference_docs.errors.extraction_failed"))
    end
  end
end
