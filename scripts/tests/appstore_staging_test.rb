require 'minitest/autorun'
require 'tmpdir'
require 'open3'

class AppstoreStagingTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def stage(version, log)
    # A shell function takes precedence over all PATH entries, including the
    # installed asc binary. These contract checks never contact Apple.
    command = <<~'BASH'
      asc() { printf '%s\n' "$@" > "$MARBLE_STAGING_ARGS"; }
      export -f asc
      exec bash "$@"
    BASH
    env = {
      'ASC_KEY_ID' => 'test-key', 'ASC_ISSUER_ID' => 'test-issuer',
      'ASC_PRIVATE_KEY_B64' => 'test-placeholder', 'MARBLE_STAGING_ARGS' => log
    }
    Open3.capture3(env, 'bash', '-c', command, 'staging-test',
                   File.join(ROOT, 'scripts/ci_appstore.sh'), 'stage', '--version', version,
                   '--build', 'test-build', '--confirm', '--dry-run')
  end

  def test_stage_passes_the_metadata_root_with_both_app_info_and_versions
    Dir.mktmpdir do |directory|
      log = File.join(directory, 'arguments')
      _, error, status = stage('2.7', log)
      assert status.success?, error
      arguments = File.readlines(log, chomp: true)
      metadata = arguments.fetch(arguments.index('--metadata-dir') + 1)
      assert File.directory?(File.join(metadata, 'app-info'))
      assert File.directory?(File.join(metadata, 'version', '2.7'))
      assert_includes arguments, '--dry-run'
    end
  end

  def test_unknown_version_stops_before_staging
    Dir.mktmpdir do |directory|
      log = File.join(directory, 'arguments')
      _, _, status = stage('99.99.99', log)
      refute status.success?
      refute File.exist?(log)
    end
  end
end
