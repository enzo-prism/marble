# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../verify_migration_probe"

class MigrationProbeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("marble-migration-probe-test")
    @store = File.join(@dir, "Marble.store")
    File.write(@store, "fixture")
    @expected = { "exercise_id" => "AABB", "exercise_name" => "User exercise",
                  "session_id" => "CCDD", "session_title" => "User workout",
                  "session_notes" => "My notes", "session_started_at" => 800000000,
                  "session_ended_at" => 800003600 }
    @marker = @expected.merge("token" => "new-launch", "pid" => 123, "store_path" => @store)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def verify(marker = @marker)
    MigrationProbe.verify!(@expected, marker, token: "new-launch", pid: "123", store_path: @store)
  end

  def test_accepts_current_launch_that_read_retained_user_data
    assert verify
  end

  def test_rejects_stale_launch_marker_even_with_identical_data
    assert_raises(RuntimeError) { verify(@marker.merge("token" => "previous-launch")) }
  end

  def test_rejects_marker_from_different_process
    assert_raises(RuntimeError) { verify(@marker.merge("pid" => 456)) }
  end

  def test_rejects_different_store_even_with_identical_rows
    other = File.join(@dir, "replacement.store")
    File.write(other, "fixture")
    assert_raises(RuntimeError) { verify(@marker.merge("store_path" => other)) }
  end

  def test_rejects_missing_or_changed_user_fields
    @expected.each_key do |key|
      assert_raises(RuntimeError) { verify(@marker.merge(key => "changed")) }
      assert_raises(KeyError) { verify(@marker.reject { |k, _| k == key }) }
    end
  end

  def test_rejects_marker_without_actual_store
    File.unlink(@store)
    assert_raises(Errno::ENOENT) { verify }
  end

  def test_accepts_equivalent_canonical_store_path
    alias_path = File.join(@dir, "alias.store")
    File.symlink(@store, alias_path)
    assert verify(@marker.merge("store_path" => alias_path))
  end
end
