require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    ds = DataSource.new(
      country_code:  "PT",
      name:          "Portal BASE",
      source_type:   "api",
      adapter_class: "PublicContracts::PT::PortalBaseClient"
    )
    assert ds.valid?
  end

  test "invalid without country_code" do
    ds = DataSource.new(name: "X", source_type: "api", adapter_class: "X")
    assert_not ds.valid?
    assert_includes ds.errors[:country_code], "can't be blank"
  end

  test "invalid without name" do
    ds = DataSource.new(country_code: "PT", source_type: "api", adapter_class: "X")
    assert_not ds.valid?
  end

  test "invalid without adapter_class" do
    ds = DataSource.new(country_code: "PT", name: "X", source_type: "api")
    assert_not ds.valid?
  end

  test "invalid with unknown source_type" do
    ds = DataSource.new(country_code: "PT", name: "X", source_type: "ftp", adapter_class: "X")
    assert_not ds.valid?
  end

  test "valid source_types are api scraper csv" do
    %w[api scraper csv].each do |t|
      ds = DataSource.new(country_code: "PT", name: "X", source_type: t, adapter_class: "X")
      assert ds.valid?, "expected #{t} to be valid"
    end
  end

  test "default status is inactive" do
    ds = DataSource.new
    assert_equal "inactive", ds.status
  end

  test "status enum transitions" do
    ds = data_sources(:portal_base)
    ds.active!
    assert ds.active?
    ds.error!
    assert ds.error?
    ds.inactive!
    assert ds.inactive?
  end

  test "config_hash returns empty hash when config is nil" do
    ds = DataSource.new
    assert_equal({}, ds.config_hash)
  end

  test "config_hash parses JSON string" do
    ds = DataSource.new(config: '{"api_key":"secret"}')
    assert_equal({ "api_key" => "secret" }, ds.config_hash)
  end

  test "config_hash returns hash when config is already a hash" do
    ds = DataSource.new
    ds.config = { "key" => "val" }
    assert_equal({ "key" => "val" }, ds.config_hash)
  end

  test "has many contracts" do
    ds = data_sources(:portal_base)
    assert_respond_to ds, :contracts
  end
end
