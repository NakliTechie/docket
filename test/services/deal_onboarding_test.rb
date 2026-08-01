require "test_helper"

class DealOnboardingTest < ActiveSupport::TestCase
  setup do
    @template = ProjectTemplate.create!(name: "Study pack", key_prefix: "ENG")
    @template.project_template_items.create!(title: "Feasibility study", kind: :task,
                                             priority: :high, due_offset_days: 5, position: 1)
    @actor = users(:admin)
  end

  def open_deal
    Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales), contact: contacts(:asha),
                 organisation: organisations(:dpg), owner: @actor)
  end

  def won_deal
    Deal.create!(name: "Won job", pipeline: pipelines(:sales), pipeline_stage: pipeline_stages(:sales_won),
                 contact: contacts(:asha), organisation: organisations(:dpg), owner: @actor)
  end

  test "engagement mode starts an engagement project from an OPEN deal with study links" do
    deal = open_deal
    project = DealOnboarding.call(deal: deal, template: @template, actor: @actor, mode: :engagement)

    assert project.kind_engagement?
    assert_equal "Engagement — RFQ machining", project.name
    assert_equal deal, project.onboarding_deal
    item = project.work_items.sole
    assert_equal "Feasibility study", item.title
    assert item.work_links.relation_study_for.exists?(linkable: deal), "study WorkItem is WorkLinked to the deal"
    refute item.work_links.relation_onboarding_for.exists?
  end

  test "engagement mode refuses a won deal" do
    error = assert_raises(DealOnboarding::Error) do
      DealOnboarding.call(deal: won_deal, template: @template, actor: @actor, mode: :engagement)
    end
    assert_match "open deal", error.message
  end

  test "the default onboarding path is unchanged (won-only, onboarding kind + relation)" do
    project = DealOnboarding.call(deal: won_deal, template: @template, actor: @actor)
    assert project.kind_onboarding?
    assert_equal "Onboarding — Won job", project.name
    assert project.work_items.sole.work_links.relation_onboarding_for.exists?

    assert_raises(DealOnboarding::Error) do
      DealOnboarding.call(deal: open_deal, template: @template, actor: @actor) # onboarding still refuses open
    end
  end

  test "one project per deal — engagement then onboarding returns the SAME project" do
    deal = open_deal
    engagement = DealOnboarding.call(deal: deal, template: @template, actor: @actor, mode: :engagement)

    deal.update_columns(status: Deal.statuses[:won]) # deal is won after the quote is accepted
    assert_no_difference "Project.count" do
      again = DealOnboarding.call(deal: deal.reload, template: @template, actor: @actor)
      assert_equal engagement, again
    end
  end

  test "an unknown mode raises" do
    assert_raises(DealOnboarding::Error) do
      DealOnboarding.call(deal: open_deal, template: @template, actor: @actor, mode: :bogus)
    end
  end
end
