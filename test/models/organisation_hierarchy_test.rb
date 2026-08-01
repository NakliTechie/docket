require "test_helper"

class OrganisationHierarchyTest < ActiveSupport::TestCase
  def org(name, parent: nil)
    Organisation.create!(name: name, kind: "company", parent: parent)
  end

  test "ancestors walk up the parent chain; root? is true only at the top" do
    root = org("Root")
    mid = org("Mid", parent: root)
    leaf = org("Leaf", parent: mid)
    assert_equal [ mid, root ], leaf.ancestors
    assert root.root?
    refute leaf.root?
  end

  test "self_and_descendants collects the whole subtree" do
    root = org("Root")
    a = org("A", parent: root)
    b = org("B", parent: root)
    a1 = org("A1", parent: a)
    assert_equal [ root, a, b, a1 ].map(&:id).sort, root.self_and_descendants.map(&:id).sort
  end

  test "an account cannot be its own parent" do
    solo = org("Solo")
    solo.parent = solo
    refute solo.valid?
    assert_match(/itself/, solo.errors[:parent].join)
  end

  test "a parent cannot be one of the account's sub-accounts (no loop)" do
    root = org("Root")
    child = org("Child", parent: root)
    root.parent = child
    refute root.valid?
    assert_match(/loop/, root.errors[:parent].join)
  end

  test "deals_including_descendants rolls up sub-account deals" do
    root = org("Root")
    sub = org("Sub", parent: root)
    c1 = Contact.create!(name: "c1", email: "c1@x.example", organisation: root)
    c2 = Contact.create!(name: "c2", email: "c2@x.example", organisation: sub)
    root_deal = Deal.create!(name: "root deal", pipeline: pipelines(:sales), organisation: root, contact: c1)
    sub_deal = Deal.create!(name: "sub deal", pipeline: pipelines(:sales), organisation: sub, contact: c2)

    rolled = root.deals_including_descendants
    assert_includes rolled, root_deal
    assert_includes rolled, sub_deal
  end

  test "cases_including_descendants rolls up sub-account cases" do
    root = org("Root")
    sub = org("Sub", parent: root)
    contact = Contact.create!(name: "c", email: "c@x.example", organisation: sub)
    kase = Case.create!(subject: "issue", contact: contact)
    assert_includes root.cases_including_descendants, kase
  end
end
