# Headless policy for the in-console knowledge-base search (PG3): any staffer
# who can read cases can search the KB to help compose a reply.
class KnowledgeBasePolicy < ApplicationPolicy
  def search? = permit?("case:read")
end
