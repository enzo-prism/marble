require 'minitest/autorun'
require 'open3'

class SnapshotShardingTest < Minitest::Test
  SCRIPT = File.expand_path('../run_snapshot_suite.sh', __dir__)

  def groups(index: 0, count: 1)
    output, error, status = Open3.capture3(
      { 'SNAPSHOT_LIST_ONLY' => '1', 'SNAPSHOT_SUITE' => 'full',
        'SNAPSHOT_GROUPS_OVERRIDE' => '', 'SNAPSHOT_SHARD_INDEX' => index.to_s,
        'SNAPSHOT_SHARD_COUNT' => count.to_s }, 'bash', SCRIPT
    )
    assert status.success?, error
    output.lines.map(&:strip).select { |line| line.start_with?('MarbleSnapshotTests/') }
  end

  def test_four_shards_partition_every_full_group_exactly_once
    all = groups
    shards = (0...4).map { |index| groups(index: index, count: 4) }
    assert_equal all.sort, shards.flatten.sort
    assert_equal all.length, shards.flatten.uniq.length
    assert shards.all? { |shard| shard.length.between?(10, 11) }
    assert_equal 1, shards.count { |shard| shard.include?('MarbleSnapshotTests/WorkoutHistorySnapshotTests') }
  end

  def test_invalid_or_out_of_range_shards_fail
    [['4', '4'], ['-1', '4'], ['08', '4'], ['0', '0'], ['0', '101']].each do |index, count|
      _, _, status = Open3.capture3({ 'SNAPSHOT_LIST_ONLY' => '1', 'SNAPSHOT_SHARD_INDEX' => index, 'SNAPSHOT_SHARD_COUNT' => count }, 'bash', SCRIPT)
      refute status.success?, "#{index}/#{count}"
    end
  end
end
