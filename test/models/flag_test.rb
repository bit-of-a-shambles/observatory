require "test_helper"

class FlagTest < ActiveSupport::TestCase
  test "valid flag" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      details: { "rule" => "A2/A3" },
      fired_at: Time.current
    )

    assert flag.valid?
  end

  test "invalid without contract" do
    flag = Flag.new(
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    assert_not flag.valid?
  end

  test "invalid without flag_type" do
    flag = Flag.new(
      contract: contracts(:one),
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    assert_not flag.valid?
  end

  test "invalid without severity" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: nil,
      score: 40,
      fired_at: Time.current
    )

    assert_not flag.valid?
  end

  test "invalid without score" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      fired_at: Time.current
    )

    assert_not flag.valid?
  end

  test "invalid without fired_at" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40
    )

    assert_not flag.valid?
  end

  test "flag_type must be unique per contract" do
    attrs = {
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    }

    Flag.create!(attrs)
    duplicate = Flag.new(attrs)

    assert_not duplicate.valid?
  end

  test "same flag_type allowed for different contracts" do
    Flag.create!(
      contract: contracts(:one),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    other = Flag.new(
      contract: contracts(:two),
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    assert other.valid?
  end
end
