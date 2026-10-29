require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class ReviewSubmissionTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, 'asc'), <<~'STUB')
      #!/usr/bin/env ruby
      require 'json'
      action = ARGV[1]
      exit 9 if ENV['FAIL'] == action
      draft = {id: 'draft', attributes: {state: 'READY_FOR_REVIEW'}}
      data = case action
      when 'submissions-list' then Array.new(ENV.fetch('COUNT', '0').to_i, draft)
      when 'submissions-create' then draft
      when 'items-add' then {}
      when 'items-list' then Array.new(ENV.fetch('ITEM_COUNT', '1').to_i, {relationships: {appStoreVersion: {data: {id: ENV.fetch('VERSION', 'expected-version')}}}})
      else abort 'Unexpected command'
      end
      puts JSON.generate(data: data)
    STUB
    FileUtils.chmod(0o755, File.join(@dir, 'asc'))
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end
  def run_draft(env = {})
    Open3.capture3({'PATH' => "#{@dir}:#{ENV['PATH']}"}.merge(env), 'bash', '-c', 'set -euo pipefail; source "$1"; id="$(marble_review_submission_id app IOS expected-version)"; printf "%s" "$id"', 'test', File.join(ROOT, 'scripts/lib/review_submission.sh'))
  end
  def test_creates_and_verifies_exact_item
    out, err, status = run_draft
    assert status.success?, err
    assert_equal 'draft', out
  end
  def test_retry_reuses_exact_existing_draft
    assert run_draft('COUNT' => '1').last.success?
  end
  def test_network_and_mutation_failures_never_succeed
    %w[submissions-list submissions-create items-add items-list].each do |action|
      refute run_draft('FAIL' => action).last.success?, action
    end
  end
  def test_unrelated_ambiguous_or_empty_drafts_fail
    [{'COUNT' => '2'}, {'COUNT' => '1', 'VERSION' => 'other'}, {'COUNT' => '1', 'ITEM_COUNT' => '2'}, {'COUNT' => '1', 'ITEM_COUNT' => '0'}].each do |env|
      refute run_draft(env).last.success?, env.inspect
    end
  end
end
