#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

# Verify artifact integrity first, then readiness and identity. An integrity-only
# check is deliberately insufficient: a perfectly preserved failed run is not ready.
manifest_path, root, version = ARGV
abort "Usage: verify_release_candidate.rb MANIFEST REPO VERSION" unless version
root = File.expand_path(root)
abort "Release evidence is required" if manifest_path.to_s.empty?
abort "Evidence integrity check failed" unless system("ruby", File.join(root, "scripts/release_evidence_manifest.rb"), "verify", manifest_path)
manifest = JSON.parse(File.read(manifest_path))
sha, status = Open3.capture2("git", "-C", root, "rev-parse", "HEAD")
abort "Cannot resolve candidate" unless status.success?
candidate = manifest.fetch("candidate")
abort "Dirty or legacy run is not production evidence" unless candidate["clean_run"] == true
project = File.read(File.join(root, "marble.xcodeproj/project.pbxproj"))
builds = project.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.uniq
abort "Candidate SHA mismatch" unless candidate.fetch("git_sha") == sha.strip
abort "Candidate version mismatch" unless candidate.fetch("marketing_version") == version
abort "Candidate build mismatch" unless builds == [candidate.fetch("build_number").to_s]
abort "Candidate has uncommitted changes" unless system("git", "-C", root, "diff", "--quiet", "HEAD", "--")
untracked, status = Open3.capture2("git", "-C", root, "ls-files", "--others", "--exclude-standard")
abort "Candidate has untracked files; keep release evidence outside the checkout" unless status.success? && untracked.strip.empty?
required = %w[unit snapshot ui accessibility migration]
gates = manifest.fetch("gates")
abort "Incomplete release checks" unless gates.map { |g| g.fetch("name") }.sort == required.sort
abort "Release checks did not pass" unless manifest.dig("run", "overall_status") == "passed" && gates.all? { |g| g["status"] == "passed" && g["exit_code"] == 0 }
abort "Evidence has no artifacts" if manifest.fetch("artifacts").empty?

# Physical checks are explicit evidence, never inferred from simulator success.
signoff_path = ENV["RELEASE_DEVICE_SIGNOFF"].to_s
abort "Physical-device signoff required (RELEASE_DEVICE_SIGNOFF)" if signoff_path.empty?
signoff = JSON.parse(File.read(signoff_path))
abort "Physical signoff belongs to another candidate" unless signoff["git_sha"] == sha.strip && signoff["build_number"].to_s == builds.first
abort "Physical signoff is incomplete" unless %w[device os tested_at reviewer].all? { |key| !signoff[key].to_s.strip.empty? }
checks = %w[launch logging draft_resume history_repeat accessibility performance]
abort "Physical checks did not pass" unless checks.all? { |key| signoff.fetch("checks", {})[key] == "passed" }

receipt_path = ENV["RELEASE_UPLOAD_RECEIPT"].to_s
abort "Upload receipt required (RELEASE_UPLOAD_RECEIPT)" if receipt_path.empty?
receipt = JSON.parse(File.read(receipt_path))
abort "Unsupported upload receipt" unless receipt["schema_version"] == 1
abort "Uploaded source differs from tested source" unless receipt["git_sha"] == sha.strip
abort "Uploaded version/build differs from tested candidate" unless receipt["marketing_version"] == version && receipt["build_number"].to_s == builds.first
abort "Upload receipt belongs to another app" unless receipt["app_id"] == ENV.fetch("ASC_APP_ID", "6757725234")
abort "Upload receipt incomplete" unless %w[build_id uploaded_at archive_identity].all? { |key| !receipt[key].to_s.strip.empty? }
abort "Upload receipt missing IPA hash" unless receipt["ipa_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
if ENV["RELEASE_UPLOAD_RUN_ID"]
  abort "Receipt belongs to another upload run" unless receipt["github_run_id"] == ENV["RELEASE_UPLOAD_RUN_ID"]
  abort "Receipt belongs to another repository" unless receipt["github_repository"] == ENV["GITHUB_REPOSITORY"]
end
puts "Release candidate verified: #{version} (#{builds.first}) #{sha.strip}"
