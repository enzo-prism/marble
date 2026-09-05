#!/usr/bin/env ruby
# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

class ReleaseCandidateTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  def setup
    @dir = Dir.mktmpdir("marble-release-test-")
    FileUtils.mkdir_p(File.join(@dir, "scripts"))
    FileUtils.cp(File.join(ROOT, "scripts/release_evidence_manifest.rb"), File.join(@dir, "scripts"))
    FileUtils.mkdir_p(File.join(@dir, "marble.xcodeproj"))
    File.write(File.join(@dir, "marble.xcodeproj/project.pbxproj"), "CURRENT_PROJECT_VERSION = 64;\n")
    system("git", "init", "-q", @dir)
    system("git", "-C", @dir, "add", ".")
    system("git", "-C", @dir, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
    @sha = Open3.capture2("git", "-C", @dir, "rev-parse", "HEAD").first.strip
    @run = Dir.mktmpdir("marble-evidence-test-")
    FileUtils.mkdir_p(File.join(@run, ".evidence/gates"))
    write(".evidence/run.json", {git_sha: @sha, clean_run: true, marketing_version: "2.5", build_number: "64", run_id: "test", started_at: "2026-09-04T00:00:00Z", requested_gates: %w[unit snapshot ui accessibility migration]})
    %w[unit snapshot ui accessibility migration].each { |name| write(".evidence/gates/#{name}.json", {name: name, status: "passed", exit_code: 0}) }
    File.write(File.join(@run, "result.log"), "fixture test evidence\n")
    Open3.capture3("ruby", File.join(ROOT, "scripts/release_evidence_manifest.rb"), "generate", @run)
    @signoff = File.join(@run, ".evidence/device.json")
    File.write(@signoff, JSON.generate({git_sha: @sha, build_number: "64", device: "fixture", os: "26.5", tested_at: "2026-09-04", reviewer: "fixture", checks: %w[launch logging draft_resume history_repeat accessibility performance].to_h { |key| [key, "passed"] }}))
    @receipt = File.join(@run, ".evidence/upload.json")
    File.write(@receipt, JSON.generate({schema_version: 1, git_sha: @sha, app_id: "6757725234", marketing_version: "2.5", build_number: "64", build_id: "fixture-build-id", uploaded_at: "2026-09-04", archive_identity: "fixture", ipa_sha256: "a" * 64}))
  end
  def teardown
    FileUtils.remove_entry(@dir)
    FileUtils.remove_entry(@run)
  end
  def write(path, object)
    File.write(File.join(@run, path), JSON.generate(object))
  end
  def verify
    Open3.capture3({"RELEASE_DEVICE_SIGNOFF" => @signoff, "RELEASE_UPLOAD_RECEIPT" => @receipt, "RELEASE_UPLOAD_RUN_ID" => nil}, "ruby", File.join(ROOT, "scripts/verify_release_candidate.rb"), File.join(@run, "manifest.json"), @dir, "2.5").last.success?
  end
  def mutate_manifest
    path = File.join(@run, "manifest.json")
    data = JSON.parse(File.read(path))
    yield data
    File.write(path, JSON.generate(data))
  end
  def test_accepts_complete_matching_evidence
    assert verify
  end
  def test_rejects_different_sha
    mutate_manifest { |m| m["candidate"]["git_sha"] = "other" }
    refute verify
  end
  def test_rejects_missing_gate
    mutate_manifest { |m| m["gates"].pop }
    refute verify
  end
  def test_rejects_failed_gate
    mutate_manifest { |m| m["gates"][0]["status"] = "failed" }
    refute verify
  end
  def test_rejects_changed_artifact
    File.write(File.join(@run, "result.log"), "changed")
    refute verify
  end
  def test_rejects_missing_device_check
    data = JSON.parse(File.read(@signoff))
    data["checks"].delete("performance")
    File.write(@signoff, JSON.generate(data))
    refute verify
  end
  def test_rejects_different_build
    mutate_manifest { |m| m["candidate"]["build_number"] = "63" }
    refute verify
  end
  def test_rejects_dirty_evidence_even_when_checkout_is_clean
    mutate_manifest { |m| m["candidate"]["clean_run"] = false }
    refute verify
  end
  def test_rejects_legacy_evidence_without_clean_run
    mutate_manifest { |m| m["candidate"].delete("clean_run") }
    refute verify
  end
  def test_rejects_upload_from_different_source_with_same_build
    data = JSON.parse(File.read(@receipt))
    data["git_sha"] = "b" * 40
    File.write(@receipt, JSON.generate(data))
    refute verify
  end
  def test_rejects_receipt_from_another_app
    data = JSON.parse(File.read(@receipt))
    data["app_id"] = "another-app"
    File.write(@receipt, JSON.generate(data))
    refute verify
  end
  def test_rejects_missing_upload_receipt
    FileUtils.remove_file(@receipt)
    refute verify
  end
  def test_upload_receipt_is_exclusive_and_preserves_original
    ipa = File.join(@run, "fixture.ipa")
    File.write(ipa, "fixture archive")
    directory = File.join(@run, "receipts")
    args = ["ruby", File.join(ROOT, "scripts/write_upload_receipt.rb"), directory, @sha, "6757725234", "2.5", "64", "uploaded-id", ipa]
    assert Open3.capture3({"GITHUB_RUN_ID" => nil}, *args).last.success?
    receipt = Dir[File.join(directory, "*.json")].first
    original = File.read(receipt)
    data = JSON.parse(original)
    assert_equal "uploaded-id", data["build_id"]
    assert_equal @sha, data["git_sha"]
    assert_equal 64, data["ipa_sha256"].length
    refute Open3.capture3({"GITHUB_RUN_ID" => nil}, *args).last.success?
    assert_equal original, File.read(receipt)
  end
end
