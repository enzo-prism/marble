require 'minitest/autorun'
require 'open3'
require 'fileutils'
require 'tmpdir'

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

  def test_non_history_groups_share_one_xcodebuild
    result = run_suite_with_fakes(
      'MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty,' \
      'MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated,' \
      'MarbleSnapshotTests/TrendsSnapshotTests/testTrendsEmpty,' \
      'MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated,' \
      'MarbleSnapshotTests/SplitSnapshotTests/testSplitEmpty'
    )
    assert result[:status].success?, result[:error]
    assert_equal 1, result[:xcodebuild].length,
                 "expected one batched xcodebuild, got #{result[:xcodebuild].inspect}"
    flags = only_testing(result[:xcodebuild].first)
    assert_equal 5, flags.length
    %w[
      MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty
      MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated
      MarbleSnapshotTests/TrendsSnapshotTests/testTrendsEmpty
      MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated
      MarbleSnapshotTests/SplitSnapshotTests/testSplitEmpty
    ].each { |group| assert_includes flags, group }
    refute_includes result[:xcrun].join("\n"), 'shutdown'
    assert result[:xcrun].any? { |line| line.include?('terminate') && line.include?('Prism.marble') }
    assert result[:xcrun].any? { |line| line.include?('bootstatus') }
  end

  def test_history_keeps_two_launches_and_does_not_drop_batched_tests
    result = run_suite_with_fakes(
      'MarbleSnapshotTests/WorkoutComposerSnapshotTests,' \
      'MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty,' \
      'MarbleSnapshotTests/WorkoutHistorySnapshotTests'
    )
    assert result[:status].success?, result[:error]
    assert_equal 3, result[:xcodebuild].length,
                 "expected 1 batched + 2 History launches, got #{result[:xcodebuild].inspect}"
    batched = only_testing(result[:xcodebuild].first)
    assert_equal %w[
      MarbleSnapshotTests/WorkoutComposerSnapshotTests
      MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty
    ].sort, batched.sort
    history = result[:xcodebuild][1..].map { |line| only_testing(line) }
    assert history.all? { |flags| flags == ['MarbleSnapshotTests/WorkoutHistorySnapshotTests'] }
    refute_includes result[:xcrun].join("\n"), 'shutdown'
  end

  private

  def only_testing(line)
    line.scan(/-only-testing:(\S+)/).flatten
  end

  def run_suite_with_fakes(groups_override)
    Dir.mktmpdir('marble-snapshot-fakes-') do |directory|
      bin = File.join(directory, 'bin')
      log = File.join(directory, 'log')
      FileUtils.mkdir_p(bin)
      FileUtils.mkdir_p(log)
      write_fake_xcodebuild(File.join(bin, 'xcodebuild'), File.join(log, 'xcodebuild'))
      write_fake_xcrun(File.join(bin, 'xcrun'), File.join(log, 'xcrun'))
      env = {
        'PATH' => "#{bin}:#{ENV.fetch('PATH')}",
        'MARBLE_SIMULATOR_ID' => 'DEADBEEF-SIM',
        'DERIVED_DATA_PATH' => File.join(directory, 'DerivedData'),
        'RELEASE_EVIDENCE_RUN_DIR' => File.join(directory, 'evidence'),
        'RELEASE_EVIDENCE_SUITE' => 'snapshot',
        'RELEASE_EVIDENCE_CAPTURE_XCRESULT' => '1',
        'SNAPSHOT_LIST_ONLY' => '0',
        'SNAPSHOT_SUITE' => 'full',
        'SNAPSHOT_GROUPS_OVERRIDE' => groups_override,
        'SNAPSHOT_SHARD_COUNT' => '1',
        'SNAPSHOT_SHARD_INDEX' => '0'
      }
      FileUtils.mkdir_p(env['RELEASE_EVIDENCE_RUN_DIR'])
      output, error, status = Open3.capture3(env, 'bash', SCRIPT)
      {
        status: status,
        output: output,
        error: error,
        xcodebuild: File.exist?(File.join(log, 'xcodebuild')) ? File.readlines(File.join(log, 'xcodebuild'), chomp: true) : [],
        xcrun: File.exist?(File.join(log, 'xcrun')) ? File.readlines(File.join(log, 'xcrun'), chomp: true) : []
      }
    end
  end

  def write_fake_xcodebuild(path, log)
    File.write(path, <<~BASH)
      #!/usr/bin/env bash
      set -euo pipefail
      printf '%s\\n' "$*" >> #{log.inspect}
      bundle=""
      previous=""
      for argument in "$@"; do
        if [[ "$previous" == "-resultBundlePath" ]]; then
          bundle=$argument
        fi
        previous=$argument
      done
      if [[ -n "$bundle" ]]; then
        mkdir -p "$bundle"
        printf '%s\\n' "fake-xcresult" > "$bundle/Info.plist"
      fi
      printf '%s\\n' "Test Case '-[Fake testBatched]' started."
      printf '%s\\n' "Test Case '-[Fake testBatched]' passed (0.001 seconds)."
      printf '%s\\n' "** TEST SUCCEEDED **"
    BASH
    File.chmod(0o755, path)
  end

  def write_fake_xcrun(path, log)
    File.write(path, <<~BASH)
      #!/usr/bin/env bash
      set -euo pipefail
      printf '%s\\n' "$*" >> #{log.inspect}
      if [[ "${1:-}" == simctl && "${2:-}" == ui && $# -eq 4 ]]; then
        printf '%s\\n' "large"
      fi
      exit 0
    BASH
    File.chmod(0o755, path)
  end
end
