# Headless policy for the in-console knowledge-base search (PG3): any staffer
# with knowledge-read authority can search the KB to help compose a reply.
class KnowledgeBasePolicy < ApplicationPolicy
  def search? = permit?("knowledge:read")
end
