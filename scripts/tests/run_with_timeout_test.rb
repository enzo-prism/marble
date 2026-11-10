# frozen_string_literal: true
require "minitest/autorun"
require "open3"

class RunWithTimeoutTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "scripts/run_with_timeout.sh")

  def test_completes_before_deadline
    stdout, stderr, status = Open3.capture3("bash", SCRIPT, "5", "true")
    assert status.success?, stderr
    assert_equal "", stdout
  end

  def test_kills_a_hung_command_with_a_clear_error
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, status = Open3.capture3("bash", SCRIPT, "1", "sleep", "30")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    refute status.success?
    assert_equal 124, status.exitstatus
    assert_match(/exceeded 1s and was killed/, stderr)
    assert_operator elapsed, :<, 10
  end

  def test_kills_term_ignoring_descendants_after_the_leader_exits
    env = { "MARBLE_TIMEOUT_GRACE_SECONDS" => "1" }
    child = 'python3 -c "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)"'
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _stdout, stderr, status = Open3.capture3(
      env,
      "bash", SCRIPT, "1", "bash", "-c", "#{child} & wait"
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    refute status.success?
    assert_equal 124, status.exitstatus
    assert_match(/exceeded 1s and was killed/, stderr)
    assert_operator elapsed, :<, 8
  end
end
