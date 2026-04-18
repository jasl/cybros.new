#!/usr/bin/env ruby

require_relative "../lib/cybros_nexus"

config = CybrosNexus::Config.load
browser_host = CybrosNexus::Browser::Host.new
manifest = CybrosNexus::Session::RuntimeManifest.new(
  config: config,
  browser_available: browser_host.available?,
  browser_unavailable_reason: browser_host.unavailable_reason
)
server = CybrosNexus::HTTP::Server.new(config: config, manifest: manifest)

trap("INT") do
  server.stop
end

trap("TERM") do
  server.stop
end

server.start
browser_host.shutdown
