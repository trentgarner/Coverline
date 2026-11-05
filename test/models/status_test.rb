require "test_helper"

class StatusTest < ActiveSupport::TestCase
  def build(attrs = {})
    Status.new({ organization: organizations(:summit), name: "Training", color: "#26a69a", category: "other" }.merge(attrs))
  end

  test "a valid status" do
    assert build.valid?
  end

  test "name is required and unique per organization, ignoring case" do
    assert_not build(name: "").valid?
    assert_not build(name: "available").valid?
    assert build(name: "Available", organization: organizations(:other)).tap { |s| s.name = "Available Elsewhere" }.valid?
  end

  test "color must be a six digit hex" do
    assert build(color: "#abc123").valid?
    [ "red", "#abc", "abc123", "#gggggg", "" ].each { |c| assert_not build(color: c).valid?, c }
  end

  test "category must be one of the plan's eight" do
    assert_equal %w[ready on_call wrap_up break lunch meeting offline other], Status::CATEGORIES
    assert_not build(category: "napping").valid?
  end

  test "time limit is a positive whole number or blank" do
    assert build(time_limit_minutes: nil).valid?
    assert build(time_limit_minutes: 15).valid?
    assert_not build(time_limit_minutes: 0).valid?
    assert_not build(time_limit_minutes: -5).valid?
    assert_not build(time_limit_minutes: 2.5).valid?
  end

  test "flag defaults: Available and On Call count toward CFT; Ready, On Call, Wrap Up are productive" do
    assert_equal({ productive: true, counts_toward_cft: true }, Status.flag_defaults_for("ready"))
    assert_equal({ productive: true, counts_toward_cft: true }, Status.flag_defaults_for("on_call"))
    assert_equal({ productive: true, counts_toward_cft: false }, Status.flag_defaults_for("wrap_up"))
    %w[break lunch meeting offline other].each do |c|
      assert_equal({ productive: false, counts_toward_cft: false }, Status.flag_defaults_for(c), c)
    end
  end

  test "several phone codes map to one status, saved with it" do
    s = build(name: "Coaching", phone_codes_text: "AUX-9\nCoach, COACHING\n  \nAUX-9")
    assert s.save_with_codes
    assert_equal %w[AUX-9 Coach COACHING].sort, s.status_codes.pluck(:phone_code).sort
  end

  test "editing the codes replaces the set" do
    s = statuses(:break)
    s.phone_codes_text = "AUX-2\nAUX-7"
    assert s.save_with_codes
    assert_equal %w[AUX-2 AUX-7], s.reload.status_codes.pluck(:phone_code).sort
  end

  test "a phone code can map to only one status in the organization, ignoring case" do
    s = build(name: "Coaching", phone_codes_text: "ready")
    assert_not s.save_with_codes
    assert_match "already used", s.errors[:phone_codes_text].to_sentence
    assert_not Status.exists?(name: "Coaching")
  end

  test "the same code is fine in another organization, and on the same status when editing" do
    assert build(name: "Elsewhere", organization: organizations(:other), phone_codes_text: "AUX-2").save_with_codes
    s = statuses(:available)
    s.phone_codes_text = "Ready"
    assert s.save_with_codes
  end

  test "codes are optional" do
    assert build(phone_codes_text: "").save_with_codes
  end

  test "ordered puts sort_order first" do
    assert_equal %w[Available On\ Call Break Offline], organizations(:summit).then { |o| Status.where(organization: o).ordered.pluck(:name) }
  end
end
