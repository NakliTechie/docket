require "test_helper"

class DealsTest < ActionDispatch::IntegrationTest
  test "the kanban board renders stage columns for the default pipeline" do
    sign_in_as users(:agent_a)
    Deal.create!(name: "On the board", pipeline: pipelines(:sales))
    get deals_path
    assert_response :success
    assert_match pipeline_stages(:sales_new).name, response.body
    assert_match "On the board", response.body
  end

  test "an agent can create a deal (lands in the first stage)" do
    sign_in_as users(:agent_a)
    assert_difference "Deal.count", 1 do
      post deals_path, params: { deal: { name: "Fresh deal", pipeline_id: pipelines(:sales).id, value: "1000" } }
    end
    deal = Deal.order(:id).last
    assert_equal pipeline_stages(:sales_new), deal.pipeline_stage
    assert_equal 100_000, deal.value_cents
  end

  test "an agent records a lost reason on a lost deal" do
    sign_in_as users(:agent_a)
    deal = Deal.create!(name: "Slipping", pipeline: pipelines(:sales), pipeline_stage: pipeline_stages(:sales_lost))
    patch deal_path(deal), params: { deal: { lost_reason: "competitor" } }
    assert_equal "competitor", deal.reload.lost_reason
  end

  test "moving a deal to a won stage closes it (the kanban drag endpoint)" do
    sign_in_as users(:agent_a)
    deal = Deal.create!(name: "To win", pipeline: pipelines(:sales))
    post move_deal_path(deal), params: { pipeline_stage_id: pipeline_stages(:sales_won).id }, as: :json
    assert_response :success
    assert deal.reload.status_won?
  end

  test "readonly cannot create deals; admin manages pipelines, agents cannot" do
    sign_in_as users(:readonly)
    assert_no_difference "Deal.count" do
      post deals_path, params: { deal: { name: "Nope", pipeline_id: pipelines(:sales).id } }
    end
    assert_response :forbidden

    sign_in_as users(:agent_a)
    get new_pipeline_path
    assert_response :forbidden

    sign_in_as users(:admin)
    get new_pipeline_path
    assert_response :success
  end
end
