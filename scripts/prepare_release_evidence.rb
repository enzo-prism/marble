#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "tmpdir"
root = ENV.fetch("EVIDENCE_ROOT")
manifests = Dir[File.join(root, "**/manifest.json")].select do |path|
  data = JSON.parse(File.read(path)) rescue {}
  data.is_a?(Hash) && data["schema_version"] == 1 && data.key?("candidate") && data.key?("gates")
end
abort "Expected exactly one candidate manifest" unless manifests.length == 1
signoff = JSON.parse(ENV.fetch("DEVICE_SIGNOFF"))
receipts = Dir[File.join(ENV.fetch("UPLOAD_RECEIPT_ROOT"), "**/*.json")]
abort "Expected exactly one upload receipt" unless receipts.length == 1
path = File.join(Dir.mktmpdir("marble-release-signoff-", ENV["RUNNER_TEMP"]), "device-signoff.json")
File.write(path, JSON.pretty_generate(signoff), mode: "wx")
File.open(ENV.fetch("GITHUB_ENV"), "a") do |file|
  file.puts("RELEASE_EVIDENCE_MANIFEST=#{manifests.first}")
  file.puts("RELEASE_DEVICE_SIGNOFF=#{path}")
  file.puts("RELEASE_UPLOAD_RECEIPT=#{receipts.first}")
end
