# frozen_string_literal: true

require "pathname"
require_relative "runtime_slot"

module Acceptance
  module Perf
    class Topology
      class << self
        def build(profile:, repo_root:, acceptance_root:, artifact_stamp:, runtime_host: "127.0.0.1", runtime_scheme: "http", runtime_base_port: 3201, proxy_base_port: 3410, container_prefix: "nexus-load")
          new(
            profile: profile,
            repo_root: Pathname.new(repo_root.to_s),
            acceptance_root: Pathname.new(acceptance_root.to_s),
            artifact_stamp: artifact_stamp,
            runtime_host: runtime_host,
            runtime_scheme: runtime_scheme,
            runtime_base_port: runtime_base_port,
            proxy_base_port: proxy_base_port,
            container_prefix: container_prefix
          )
        end
      end

      attr_reader :artifact_root, :profile_name, :run_root

      def initialize(profile:, repo_root:, acceptance_root:, artifact_stamp:, runtime_host:, runtime_scheme:, runtime_base_port:, proxy_base_port:, container_prefix:)
        @profile_name = profile.name
        @artifact_root = acceptance_root.join("artifacts", artifact_stamp)
        @run_slug = sanitize_run_slug(artifact_stamp)
        @run_root = repo_root.join("tmp", "multi-agent-runtime-core-matrix-load", @run_slug)
        @slots = build_slots(
          profile: profile,
          repo_root: repo_root,
          acceptance_root: acceptance_root,
          artifact_stamp: artifact_stamp,
          runtime_host: runtime_host,
          runtime_scheme: runtime_scheme,
          runtime_base_port: runtime_base_port,
          proxy_base_port: proxy_base_port,
          container_prefix: container_prefix
        ).freeze
      end

      def runtime_count
        @slots.length
      end

      def runtime_slot(index)
        raise IndexError, "runtime slot #{index} is out of range" if index < 1

        slot = @slots[index - 1]
        raise IndexError, "runtime slot #{index} is out of range" unless slot

        slot
      end

      def runtime_slots
        @slots.dup
      end

      private

      def build_slots(profile:, repo_root:, acceptance_root:, artifact_stamp:, runtime_host:, runtime_scheme:, runtime_base_port:, proxy_base_port:, container_prefix:)
        (1..profile.runtime_count).map do |index|
          RuntimeSlot.build(
            index: index,
            run_slug: @run_slug,
            repo_root: repo_root,
            acceptance_root: acceptance_root,
            artifact_stamp: artifact_stamp,
            runtime_host: runtime_host,
            runtime_scheme: runtime_scheme,
            runtime_base_port: runtime_base_port,
            proxy_base_port: proxy_base_port,
            container_prefix: container_prefix
          )
        end
      end

      def sanitize_run_slug(value)
        slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        raise ArgumentError, "artifact stamp must produce a non-empty run slug" if slug.empty?

        slug
      end
    end
  end
end
