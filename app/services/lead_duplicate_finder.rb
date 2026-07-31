class LeadDuplicateFinder
  def self.call(lead)
    return Lead.none if lead.merged_into_id?

    candidates = Lead.canonical.where.not(id: lead.id)
    clauses = []
    clauses << candidates.where(email: lead.email) if lead.email.present?
    clauses << candidates.where(phone: lead.phone) if lead.phone.present?
    return Lead.none if clauses.empty?

    clauses.reduce { |combined, relation| combined.or(relation) }.distinct
  end
end
