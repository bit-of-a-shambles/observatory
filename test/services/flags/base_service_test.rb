require "test_helper"

module Flags
  class BaseServiceTest < ActiveSupport::TestCase
    class TestFlagService < BaseService
      def description
        "Flags contracts with low base price"
      end

      def flag_key
        "A5_THRESHOLD_SPLIT"
      end

      def severity
        "medium"
      end

      def candidates_scope
        Contract.where("base_price < ?", 20_000)
      end

      def matches?(contract)
        contract.base_price.to_d < 19_000
      end

      def evidence(contract)
        {
          base_price: contract.base_price.to_s,
          threshold: "19000.0"
        }
      end

      def data_completeness_for(contract)
        contract.cpv_code.present? ? 1.0 : 0.5
      end
    end

    test "idempotent execution does not create duplicates" do
      service = TestFlagService.new(logger: Logger.new(nil))

      first = service.call
      second = service.call

      assert_equal 2, first[:flagged]
      assert_equal 2, first[:created]
      assert_equal 2, second[:flagged]
      assert_equal 0, second[:created]
      assert_equal 2, second[:updated]
      assert_equal 2, Flag.where(flag_key: "A5_THRESHOLD_SPLIT").count
    end

    test "upsert updates evidence and metadata when rule output changes" do
      service = TestFlagService.new(logger: Logger.new(nil))
      service.call

      contract = contracts(:one)
      contract.update!(base_price: 17_500)

      flag = Flag.find_by!(contract_id: contract.id, flag_key: "A5_THRESHOLD_SPLIT")
      original_detected_at = flag.detected_at
      original_fingerprint = flag.fingerprint

      travel 1.second do
        result = service.call
        flag.reload

        assert_equal 2, result[:updated]
        assert_not_equal original_fingerprint, flag.fingerprint
        assert_operator flag.detected_at, :>, original_detected_at
        assert_equal "17500.0", flag.evidence.fetch("base_price")
      end
    end

    test "country filter scopes candidates by country code" do
      service = TestFlagService.new(logger: Logger.new(nil))

      result = service.call(country_code: "ES")

      assert_equal 1, result[:evaluated]
      assert_equal 1, result[:flagged]
      assert_equal [ "ES" ], Flag.where(flag_key: "A5_THRESHOLD_SPLIT").distinct.pluck(:country_code)
    end

    test "dry_run evaluates but does not persist" do
      service = TestFlagService.new(logger: Logger.new(nil))

      result = service.call(dry_run: true)

      assert_equal 2, result[:flagged]
      assert_equal 0, result[:created]
      assert_equal 0, result[:updated]
      assert_equal 0, Flag.where(flag_key: "A5_THRESHOLD_SPLIT").count
    end


    test "base service default scope and scoring defaults" do
      base = BaseService.new(logger: Logger.new(nil))

      assert_equal Contract.count, base.candidates_scope.count
      assert_equal BaseService::DEFAULT_CONFIDENCE, base.confidence_for(contracts(:one))
      assert_equal BaseService::DEFAULT_DATA_COMPLETENESS, base.data_completeness_for(contracts(:one))
    end

    test "base service enforces abstract interface" do
      base = BaseService.new(logger: Logger.new(nil))

      assert_raises(NotImplementedError) { base.description }
      assert_raises(NotImplementedError) { base.flag_key }
      assert_raises(NotImplementedError) { base.severity }
      assert_raises(NotImplementedError) { base.matches?(contracts(:one)) }
      assert_raises(NotImplementedError) { base.evidence(contracts(:one)) }
    end
  end
end
