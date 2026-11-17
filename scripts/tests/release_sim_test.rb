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
      assert xcrun.any? { |line| line.include?("create marble-99-sim-unit iPhone 17 ") }
      assert xcrun.any? { |line| line.start_with?("boot AAAA-UNIT-UDID") || line.include?("boot AAAA-UNIT-UDID") }
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

  def test_github_actions_destination_requires_explicit_udid
    output, error, status = Open3.capture3(
      { "GITHUB_ACTIONS" => "true", "MARBLE_SIMULATOR_ID" => "" },
      "bash", DESTINATION
    )
    refute status.success?, output
    assert_includes error, "MARBLE_SIMULATOR_ID"

    output, error, status = Open3.capture3(
      { "GITHUB_ACTIONS" => "true", "MARBLE_SIMULATOR_ID" => "DEAD-BEEF" },
      "bash", DESTINATION
    )
    assert status.success?, error
    assert_equal "id=DEAD-BEEF", output.strip
  end

  private

  def with_fakes
    Dir.mktmpdir("marble-release-sim-") do |directory|
      bin = File.join(directory, "bin")
      log = File.join(directory, "xcrun.log")
      FileUtils.mkdir_p(bin)
      write_fake_xcrun(File.join(bin, "xcrun"), log)
      env = {
        "PATH" => "#{bin}:#{ENV.fetch("PATH")}",
        "GITHUB_ENV" => File.join(directory, "github.env"),
        "SIMCTL_BOOTSTATUS_TIMEOUT" => "2"
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
      exit 0
    BASH
    File.chmod(0o755, path)
  end
end
