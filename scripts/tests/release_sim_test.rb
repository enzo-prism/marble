# frozen_string_literal: true
require "minitest/autorun"
require "open3"
require "fileutils"
require "tmpdir"

class ReleaseSimTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CREATE = File.join(ROOT, "scripts/release_sim.sh")
  DESTINATION = File.join(ROOT, "scripts/sim_destination.sh")

  def test_create_boots_named_device_and_exports_udid
    with_fakes do |env, log|
      output, error, status = Open3.capture3(env, "bash", CREATE, "create", "marble-99-sim-unit")
      assert status.success?, "#{output}\n#{error}"
      assert_includes output, "Dedicated simulator marble-99-sim-unit AAAA-UNIT-UDID"
      exported = File.read(env.fetch("GITHUB_ENV"))
      assert_includes exported, "MARBLE_SIMULATOR_ID=AAAA-UNIT-UDID"
      assert_includes exported, "SIMULATOR_UDID=AAAA-UNIT-UDID"
      assert_includes exported, "MARBLE_SIMULATOR_NAME=marble-99-sim-unit"
      xcrun = File.readlines(log, chomp: true)
      refute xcrun.any? { |line| line.include?("list devices") }, xcrun.inspect
      shutdown_at = xcrun.index { |line| line.include?("shutdown marble-99-sim-unit") }
      delete_at = xcrun.index { |line| line.include?("delete marble-99-sim-unit") }
      create_at = xcrun.index { |line| line.include?("create marble-99-sim-unit iPhone 17 ") }
      refute_nil shutdown_at, xcrun.inspect
      refute_nil delete_at, xcrun.inspect
      refute_nil create_at, xcrun.inspect
      assert_operator shutdown_at, :<, delete_at
      assert_operator delete_at, :<, create_at
      assert xcrun.any? { |line| line.include?("boot AAAA-UNIT-UDID") }
      assert xcrun.any? { |line| line.include?("bootstatus AAAA-UNIT-UDID") }
    end
  end

  def test_create_rejects_shared_iphone_name
    with_fakes do |env, _log|
      _output, error, status = Open3.capture3(env, "bash", CREATE, "create", "iPhone 17")
      refute status.success?
      assert_includes error, "marble-"
    end
  end

  def test_delete_shuts_down_and_removes_udid
    with_fakes do |env, log|
      env["MARBLE_SIMULATOR_ID"] = "AAAA-UNIT-UDID"
      output, error, status = Open3.capture3(env, "bash", CREATE, "delete")
      assert status.success?, "#{output}\n#{error}"
      xcrun = File.readlines(log, chomp: true)
      assert xcrun.any? { |line| line.include?("shutdown AAAA-UNIT-UDID") }
      assert xcrun.any? { |line| line.include?("delete AAAA-UNIT-UDID") }
    end
  end

  def test_explicit_udid_wins_on_github_actions
    output, error, status = Open3.capture3(
      { "GITHUB_ACTIONS" => "true", "MARBLE_SIMULATOR_ID" => "DEAD-BEEF" },
      "bash", DESTINATION
    )
    assert status.success?, error
    assert_equal "id=DEAD-BEEF", output.strip
  end

  def test_bootstatus_retries_once_after_timeout
    with_fakes do |env, log|
      env["SIMCTL_BOOTSTATUS_TIMEOUT"] = "1"
      env["SIMCTL_BOOTSTATUS_FAIL_ONCE"] = "1"
      output, error, status = Open3.capture3(env, "bash", CREATE, "create", "marble-99-sim-snapshot")
      assert status.success?, "#{output}\n#{error}"
      assert_includes error, "retrying boot"
      bootstatus = File.readlines(log, chomp: true).count { |line| line.include?("bootstatus") }
      assert_equal 2, bootstatus, File.read(log)
    end
  end

  def test_github_actions_without_udid_still_looks_up_by_name
    with_fakes do |env, log|
      env["GITHUB_ACTIONS"] = "true"
      env.delete("MARBLE_SIMULATOR_ID")
      output, error, status = Open3.capture3(env, "bash", DESTINATION)
      assert status.success?, "#{output}\n#{error}"
      assert_equal "id=CI-SHARED-IPHONE", output.strip
      xcrun = File.readlines(log, chomp: true)
      assert xcrun.any? { |line| line.include?("list devices") }, xcrun.inspect
    end
  end

  private

  def with_fakes
    Dir.mktmpdir("marble-release-sim-") do |directory|
      bin = File.join(directory, "bin")
      log = File.join(directory, "xcrun.log")
      count_file = File.join(directory, "bootstatus.count")
      FileUtils.mkdir_p(bin)
      write_fake_xcrun(File.join(bin, "xcrun"), log)
      env = {
        "PATH" => "#{bin}:#{ENV.fetch("PATH")}",
        "GITHUB_ENV" => File.join(directory, "github.env"),
        "SIMCTL_BOOTSTATUS_TIMEOUT" => "2",
        "SIMCTL_BOOTSTATUS_COUNT_FILE" => count_file
      }
      File.write(env.fetch("GITHUB_ENV"), "")
      yield env, log
    end
  end

  def write_fake_xcrun(path, log)
    File.write(path, <<~BASH)
      #!/usr/bin/env bash
      set -euo pipefail
      printf '%s\\n' "$*" >> #{log.inspect}
      if [[ "${1:-}" == simctl && "${2:-}" == create ]]; then
        printf '%s\\n' "AAAA-UNIT-UDID"
        exit 0
      fi
      if [[ "${1:-}" == simctl && "${2:-}" == bootstatus ]]; then
        count_file="${SIMCTL_BOOTSTATUS_COUNT_FILE:-}"
        count=0
        if [[ -n "$count_file" && -f "$count_file" ]]; then
          count=$(cat "$count_file")
        fi
        count=$((count + 1))
        if [[ -n "$count_file" ]]; then
          printf '%s\\n' "$count" > "$count_file"
        fi
        if [[ "${SIMCTL_BOOTSTATUS_FAIL_ONCE:-}" == "1" && "$count" -eq 1 ]]; then
          sleep 3
        fi
        exit 0
      fi
      if [[ "${1:-}" == simctl && "${2:-}" == list && "${3:-}" == devices ]]; then
        printf '%s\\n' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"CI-SHARED-IPHONE","isAvailable":true}]}}'
        exit 0
      fi
      exit 0
    BASH
    File.chmod(0o755, path)
  end
end
