require "test_helper"

class OneDocketIntegrationTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "a won deal starts one onboarding project from a reusable template" do
    template = ProjectTemplate.create!(name: "Customer launch", key_prefix: "ONB")
    template.project_template_items.create!(title: "Confirm stakeholders", kind: :task,
                                            priority: :high, due_offset_days: 3, position: 1)
    deal = Deal.create!(name: "Acme renewal", pipeline: pipelines(:sales),
                        pipeline_stage: pipeline_stages(:sales_won), contact: contacts(:asha),
                        organisation: organisations(:dpg), owner: users(:admin))

    assert_difference [ "Project.count", "WorkItem.count", "WorkLink.count" ], 1 do
      post onboard_deal_path(deal), params: { project_template_id: template.id }
    end
    project = deal.reload.onboarding_project
    assert_redirected_to project_path(project)
    assert_equal template, project.project_template
    assert_equal "Confirm stakeholders", project.work_items.first.title
    assert_equal Date.current + 3, project.work_items.first.due_on
    assert project.work_items.first.work_links.relation_onboarding_for.exists?(linkable: deal)

    assert_no_difference [ "Project.count", "WorkItem.count", "WorkLink.count" ] do
      post onboard_deal_path(deal), params: { project_template_id: template.id }
    end
  end

  test "editing a project template always offers another task row" do
    template = ProjectTemplate.create!(name: "Repeatable launch", key_prefix: "RPT")
    template.project_template_items.create!(title: "Existing task", position: 1)

    get edit_project_template_path(template)

    assert_response :success
    assert_select "input[name*='project_template_items_attributes'][name$='[title]']", count: 2
  end

  test "customer 360 joins cases deals and delivery work for contacts and organisations" do
    contact = contacts(:asha)
    deal = Deal.create!(name: "360 implementation", pipeline: pipelines(:sales), contact: contact,
                        organisation: contact.organisation)
    item = work_items(:pep_one)
    WorkLink.create!(work_item: item, linkable: deal, relation: :onboarding_for,
                     created_by: users(:admin))

    get contact_path(contact)
    assert_response :success
    assert_includes response.body, cases(:pension_case).tracking_id
    assert_includes response.body, deal.name
    assert_includes response.body, item.reference

    get organisation_path(contact.organisation)
    assert_response :success
    assert_includes response.body, cases(:pension_case).tracking_id
    assert_includes response.body, deal.name
    assert_includes response.body, item.reference
  end

  test "global search respects enabled modules and finds every primary record type" do
    query = "Needle42"
    contact = Contact.create!(name: "#{query} customer", email: "needle42@example.com")
    Lead.create!(name: "#{query} lead", email: "lead-needle42@example.com")
    Deal.create!(name: "#{query} deal", pipeline: pipelines(:sales), contact: contact)
    Case.create!(subject: "#{query} case", contact: contact, channel: :staff)
    projects(:pep).work_items.create!(title: "#{query} work", reporter: users(:admin))

    get search_path, params: { q: query }

    assert_response :success
    %w[customer lead deal case work].each { |word| assert_match(/Needle42 #{word}/, response.body) }

    ActsAsTenant.current_tenant.set_feature!("crm", false)
    get search_path, params: { q: query }
    assert_response :success
    refute_match(/Needle42 lead/, response.body)
    refute_match(/Needle42 deal/, response.body)
    assert_match(/Needle42 case/, response.body)
  end
end
