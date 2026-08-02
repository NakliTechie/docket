class KnowledgeCategoryPolicy < ReferenceDocPolicy
  def create?  = permit?("knowledge:admin")
  def update?  = permit?("knowledge:admin")
  def destroy? = permit?("knowledge:admin")
end
