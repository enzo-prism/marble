# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class ASCBuildStatusTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @dir = Dir.mktmpdir
    @log = File.join(@dir, 'calls')
    File.write(File.join(@dir, 'asc'), <<~'STUB')
      #!/usr/bin/env ruby
      require 'json'
      File.open(ENV.fetch('ASC_TEST_LOG'), 'a') { |f| f.puts JSON.generate(ARGV) }
      command = ARGV.take_while { |x| !x.start_with?('--') }.join(' ')
      data = case command
      when 'builds info'
        {id: ENV.fetch('RESULT_ID', 'exact-id'), attributes: {version: '82', processingState: ENV.fetch('PROCESSING', 'VALID'), expired: ENV['EXPIRED'] == '1'}}
      when 'builds app view'
        {id: ENV.fetch('RESULT_APP', '6757725234')}
      when 'builds pre-release-version view'
        {attributes: {version: ENV.fetch('RESULT_VERSION', '2.6'), platform: 'IOS'}}
      when 'builds build-beta-detail view'
        {attributes: {internalBuildState: 'IN_BETA_TESTING', externalBuildState: 'READY_FOR_BETA_SUBMISSION'}}
      when 'validate testflight'
        exit ENV.fetch('VALIDATE_EXIT', '0').to_i
      else
        abort 'Unexpected or summary command'
      end
      puts JSON.generate(data: data)
    STUB
    FileUtils.chmod(0o755, File.join(@dir, 'asc'))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def run_status(extra = {}, *args)
    Open3.capture3({'PATH' => "#{@dir}:#{ENV.fetch('PATH')}", 'ASC_TEST_LOG' => @log}.merge(extra), 'ruby', File.join(ROOT, 'scripts/asc_build_status.rb'), '--version', '2.6', '--build', 'exact-id', *args)
  end

  def test_direct_relationship_reports_real_beta_state
    out, err, status = run_status
    assert status.success?, err
    assert_equal 'IN_BETA_TESTING', JSON.parse(out).dig('beta', 'internalBuildState')
    calls = File.readlines(@log).map { |l| JSON.parse(l) }
    assert calls.all? { |c| c.include?('--build-id') && c.include?('exact-id') }
  end

  def test_wrong_app_version_or_build_cannot_validate
    [{'RESULT_APP' => 'another'}, {'RESULT_VERSION' => '2.5'}, {'RESULT_ID' => 'other-id'}].each do |env|
      refute run_status(env, '--validate').last.success?
    end
  end

  def test_expired_and_processing_builds_fail_validation
    [{'EXPIRED' => '1'}, {'PROCESSING' => 'PROCESSING'}].each do |env|
      refute run_status(env, '--validate').last.success?
    end
  end

  def test_strict_failure_propagates
    _, _, status = run_status({'VALIDATE_EXIT' => '7'}, '--validate')
    assert_equal 7, status.exitstatus
    call = JSON.parse(File.readlines(@log).last)
    assert_includes call, '--strict'
    assert_includes call, 'exact-id'
  end

  def test_strict_success
    assert run_status({}, '--validate').last.success?
  end

  def test_build_number_mismatch
    refute run_status({}, '--build-number', '83').last.success?
  end
end
