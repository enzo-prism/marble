# frozen_string_literal: true
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class EnsureSimulatorTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "scripts/ensure_simulator.sh")
  RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"

  def setup
    @dir = Dir.mktmpdir("marble-ensure-sim-")
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    @devices = File.join(@dir, "devices.json")
    @xcrun_log = File.join(@dir, "xcrun.log")
    write_xcrun
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_devices(devices)
    File.write(@devices, JSON.generate({ "devices" => { RUNTIME => devices } }))
  end

  def write_xcrun
    path = File.join(@bin, "xcrun")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      set -euo pipefail
      printf '%s\\n' "$*" >> "#{@xcrun_log}"
      if [[ "${1:-}" != "simctl" ]]; then
        echo "unexpected xcrun $*" >&2
        exit 2
      fi
      shift
      case "${1:-}" in
        list)
          cat "#{@devices}"
          ;;
        boot|bootstatus)
          exit 0
          ;;
        *)
          echo "unexpected simctl $*" >&2
          exit 2
          ;;
      esac
    SH
    File.chmod(0o755, path)
  end

  def run_script(extra_env = {})
    env = {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "MARBLE_SIMULATOR_WAIT_SECONDS" => "1"
    }.merge(extra_env)
    Open3.capture3(env, "bash", SCRIPT)
  end

  def test_boots_a_pinned_available_simulator
    write_devices([{
      "name" => "iPhone Air",
      "udid" => "AIR-1",
      "isAvailable" => true,
      "state" => "Shutdown"
    }])
    stdout, stderr, status = run_script("MARBLE_SIMULATOR_ID" => "AIR-1")
    assert status.success?, stderr
    assert_equal "id=AIR-1\n", stdout
    log = File.read(@xcrun_log)
    assert_includes log, "simctl boot AIR-1"
    assert_includes log, "simctl bootstatus AIR-1 -b"
  end

  def test_fails_fast_when_core_simulator_has_no_devices
    write_devices([])
    stdout, stderr, status = run_script("MARBLE_SIMULATOR_ID" => "GONE")
    refute status.success?, stdout
    assert_equal 1, status.exitstatus
    assert_match(/No iPhone simulator became available for xcodebuild within 1s/, stderr)
    assert_match(/Pinned simulator GONE was missing from CoreSimulator/, stderr)
  end
end
