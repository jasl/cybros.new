# frozen_string_literal: true

module Acceptance
  module Perf
    class GateEvaluator
      def self.call(...)
        new(...).call
      end

      def initialize(profile:, metrics:, structural_failures:, completed_workload_items:)
        @profile = profile
        @metrics = metrics
        @structural_failures = Array(structural_failures)
        @completed_workload_items = completed_workload_items.to_i
      end

      def call
        contract = @profile.gate_contract
        return descriptive_result if contract.nil?

        checks = []
        checks << structural_failure_check
        checks << completed_workload_items_check(contract)
        checks.concat(required_metric_sample_checks(contract))
        checks << database_timeout_check(contract) if contract.key?("max_database_checkout_timeouts")

        {
          "kind" => contract.fetch("kind"),
          "eligible" => true,
          "passed" => checks.all? { |check| check.fetch("passed") },
          "checks" => checks,
          "failures" => checks.reject { |check| check.fetch("passed") }.map { |check| check.fetch("message") },
        }
      end

      private

      def descriptive_result
        {
          "kind" => "descriptive_baseline",
          "eligible" => false,
          "passed" => nil,
          "checks" => [],
          "failures" => [],
        }
      end

      def structural_failure_check
        {
          "name" => "structural_failures",
          "passed" => @structural_failures.empty?,
          "observed" => @structural_failures,
          "message" => @structural_failures.empty? ? "structural failures absent" : "structural failures present",
        }
      end

      def completed_workload_items_check(contract)
        expected = contract.fetch("required_completed_workload_items").to_i

        {
          "name" => "completed_workload_items",
          "passed" => @completed_workload_items == expected,
          "observed" => @completed_workload_items,
          "expected" => expected,
          "message" => "completed_workload_items expected #{expected}, observed #{@completed_workload_items}",
        }
      end

      def required_metric_sample_checks(contract)
        Array(contract["required_metric_sample_paths"]).map do |path|
          observed = dig_metric_value(path)
          observed_count = observed.to_i

          {
            "name" => "metric_sample_presence:#{path}",
            "passed" => observed_count.positive?,
            "observed" => observed,
            "expected" => "positive sample count",
            "message" => "#{path} expected positive sample count, observed #{observed.inspect}",
          }
        end
      end

      def database_timeout_check(contract)
        observed = @metrics.dig("database_checkout_pressure", "timeout_count").to_i
        expected_max = contract.fetch("max_database_checkout_timeouts").to_i

        {
          "name" => "database_checkout_timeouts",
          "passed" => observed <= expected_max,
          "observed" => observed,
          "expected" => "at most #{expected_max}",
          "message" => "database checkout timeouts expected at most #{expected_max}, observed #{observed}",
        }
      end

      def dig_metric_value(path)
        path.to_s.split(".").reduce(@metrics) do |cursor, segment|
          return nil unless cursor.is_a?(Hash)

          cursor[segment]
        end
      end
    end
  end
end
