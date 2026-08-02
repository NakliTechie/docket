require "test_helper"

class DecisioningConversationReplyTest < ActiveSupport::TestCase
  test "a recent deal reply proposes one review-gated stage advance" do
    deal = Deal.create!(name: "Reply deal", pipeline: pipelines(:sales),
                       pipeline_stage: pipeline_stages(:sales_new), contact: contacts(:asha))
    message = CrmMessage.create!(subject: deal, body: "Interested", direction: :inbound,
                                 sender_email: contacts(:asha).email, delivery_status: :recorded)

    proposal = Decisioning::Rules::ConversationReply.new.evaluate.sole
    assert_equal "confirm", proposal.decision_class.to_s
    assert_equal "advance_deal_stage", proposal.action
    assert_equal message.id, proposal.action_params["crm_message_id"]
    assert_equal pipeline_stages(:sales_qualified).id, proposal.action_params["pipeline_stage_id"]

    decision = Decisioning::Dispatcher.persist([ proposal ]).sole
    assert_equal pipeline_stages(:sales_new), deal.pipeline_stage
    Decisioning::Dispatcher.approve!(decision, approver: users(:admin))
    assert_equal pipeline_stages(:sales_qualified), deal.reload.pipeline_stage

    Decisioning::Dispatcher.reverse!(decision)
    assert_equal pipeline_stages(:sales_new), deal.reload.pipeline_stage
  end

  test "a reply never proposes an automatic terminal-stage move" do
    deal = Deal.create!(name: "Qualified deal", pipeline: pipelines(:sales),
                       pipeline_stage: pipeline_stages(:sales_qualified), contact: contacts(:asha))
    CrmMessage.create!(subject: deal, body: "Thanks", direction: :inbound,
                       sender_email: contacts(:asha).email, delivery_status: :recorded)

    assert_empty Decisioning::Rules::ConversationReply.new.evaluate
  end
end
