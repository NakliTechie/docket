# Decision-class tagging (effector seam): the accountability tier of an
# action under Indian administrative law (reasoned-order duty + non-fettering
# + audi alteram partem). decision_class drives the gate; decision_reason
# captures the human's speaking order when a decision-of-record is approved
# (a substantive, non-rubber-stamp justification — itself the legal
# requirement). Both snapshot onto the invocation so the ledger is the
# self-describing accountability record an appeal can point at.
class AddDecisionClassToConnectorInvocations < ActiveRecord::Migration[8.1]
  def change
    add_column :connector_invocations, :decision_class, :string
    add_column :connector_invocations, :decision_reason, :text
  end
end
