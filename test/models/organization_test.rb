require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "generating an API key returns it once and keeps only a digest" do
    org = organizations(:summit)
    assert_not org.api_key?
    key = org.generate_api_key!
    assert_match(/\Acvl_[\w-]{40,}\z/, key)
    assert org.reload.api_key?
    assert_equal key.first(8), org.api_key_prefix
    assert_not_includes org.settings.to_json, key, "the key itself is never stored"
    assert_equal org, Organization.find_by_api_key(key)
  end

  test "a wrong, blank or replaced key finds nothing" do
    org = organizations(:summit)
    old = org.generate_api_key!
    assert_nil Organization.find_by_api_key("cvl_wrong")
    assert_nil Organization.find_by_api_key("")
    assert_nil Organization.find_by_api_key(nil)
    new = org.generate_api_key!
    assert_nil Organization.find_by_api_key(old)
    assert_equal org, Organization.find_by_api_key(new)
  end

  test "keys are per organization" do
    a = organizations(:summit).generate_api_key!
    b = organizations(:other).generate_api_key!
    assert_equal organizations(:summit), Organization.find_by_api_key(a)
    assert_equal organizations(:other), Organization.find_by_api_key(b)
  end

  test "the Unmapped status is created on first use and remembered" do
    org = organizations(:summit)
    assert_nil org.statuses.find_by(name: "Unmapped")
    s = org.unmapped_status
    assert_equal s, org.reload.unmapped_status
    assert org.unmapped_status?(s)
    assert_not org.unmapped_status?(statuses(:available))
    assert_equal 1, org.statuses.where(name: "Unmapped").count
  end

  test "an admin who renames Unmapped doesn't cause a second one to appear" do
    org = organizations(:summit)
    s = org.unmapped_status
    s.update!(name: "Mystery")
    assert_equal s, org.reload.unmapped_status
    assert_equal 0, org.statuses.where(name: "Unmapped").count
  end
end
