# frozen_string_literal: true
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class PickIphoneSimulatorTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PICKER = File.join(ROOT, "scripts/lib/pick_iphone_simulator.py")
  RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"

  def setup
    @dir = Dir.mktmpdir("marble-sim-pick-")
    @json = File.join(@dir, "devices.json")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_devices(names)
    devices = names.map.with_index do |name, index|
      {
        "name" => name,
        "udid" => "UDID-#{index}",
        "isAvailable" => true
      }
    end
    File.write(@json, JSON.generate({ "devices" => { RUNTIME => devices } }))
  end

  def pick(preferred: "iPhone 17 Pro")
    stdout, stderr, status = Open3.capture3(
      "python3", PICKER,
      "--preferred", preferred,
      "--runtime", RUNTIME,
      "--devices-json", @json
    )
    assert status.success?, stderr
    stdout
  end

  def test_prefers_iphone_17_pro_over_air_when_15_pro_is_missing
    write_devices(["iPhone Air", "iPhone 17 Pro", "iPhone 17 Pro Max", "iPhone 17e"])
    assert_equal "UDID-1", pick(preferred: "iPhone 15 Pro")
  end

  def test_uses_exact_preferred_name_when_present
    write_devices(["iPhone 17 Pro", "iPhone Air"])
    assert_equal "UDID-0", pick(preferred: "iPhone 17 Pro")
  end

  def test_does_not_choose_air_as_the_unnamed_fallback
    write_devices(["iPhone Air", "iPhone 17"])
    assert_equal "UDID-1", pick(preferred: "iPhone 15 Pro")
  end

  def test_returns_empty_when_runtime_has_no_iphones
    File.write(@json, JSON.generate({ "devices" => { RUNTIME => [{ "name" => "iPad Pro", "udid" => "PAD", "isAvailable" => true }] } }))
    assert_equal "", pick
  end

  def test_falls_back_to_newest_ios_runtime_when_preferred_runtime_is_absent
    newer = "com.apple.CoreSimulator.SimRuntime.iOS-26-6"
    File.write(@json, JSON.generate({
      "devices" => {
        newer => [
          { "name" => "iPhone Air", "udid" => "AIR", "isAvailable" => true },
          { "name" => "iPhone 17 Pro", "udid" => "PRO", "isAvailable" => true }
        ]
      }
    }))
    assert_equal "PRO", pick(preferred: "iPhone 17 Pro")
  end
end
