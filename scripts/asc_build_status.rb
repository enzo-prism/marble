#!/usr/bin/env ruby
# Read each relationship directly: asc status can report stale beta state.
require 'json'
require 'open3'
require 'optparse'

options = {app: ENV.fetch('ASC_APP', '6757725234'), platform: 'IOS', validate: false}
OptionParser.new do |parser|
  parser.on('--app ID') { |v| options[:app] = v }
  parser.on('--version VERSION') { |v| options[:version] = v }
  parser.on('--build-number NUMBER') { |v| options[:number] = v }
  parser.on('--build ID') { |v| options[:build] = v }
  parser.on('--platform PLATFORM') { |v| options[:platform] = v }
  parser.on('--validate') { options[:validate] = true }
end.parse!
abort 'Specify --version and either --build or --build-number' unless options[:version] && (options[:build] || options[:number])

def asc_json(*args)
  output, error, status = Open3.capture3('asc', *args, '--output', 'json')
  abort "ASC read failed (#{args.join(' ')}): #{error}" unless status.success?
  JSON.parse(output)
rescue JSON::ParserError => error
  abort "ASC returned invalid JSON: #{error.message}"
end

selector = options[:build] ? ['--build-id', options[:build]] : ['--app', options[:app], '--version', options[:version], '--build-number', options[:number], '--platform', options[:platform]]
build = asc_json('builds', 'info', *selector).fetch('data')
id = build.fetch('id')
abort 'ASC returned another build ID' if options[:build] && id != options[:build]
abort 'ASC returned another build number' if options[:number] && build.dig('attributes', 'version') != options[:number]
app = asc_json('builds', 'app', 'view', '--build-id', id).fetch('data')
train = asc_json('builds', 'pre-release-version', 'view', '--build-id', id).fetch('data')
abort 'Build belongs to another app' unless app.fetch('id') == options[:app]
abort 'Build belongs to another version or platform' unless train.dig('attributes', 'version') == options[:version] && train.dig('attributes', 'platform') == options[:platform]
beta = asc_json('builds', 'build-beta-detail', 'view', '--build-id', id).fetch('data')
puts JSON.pretty_generate({app_id: app.fetch('id'), build_id: id, build_number: build.dig('attributes', 'version'), version: train.dig('attributes', 'version'), platform: train.dig('attributes', 'platform'), processing_state: build.dig('attributes', 'processingState'), expired: build.dig('attributes', 'expired'), beta: beta.fetch('attributes')})
if options[:validate]
  abort 'Build is not VALID or is expired' unless build.dig('attributes', 'processingState') == 'VALID' && build.dig('attributes', 'expired') == false
  system('asc', 'validate', 'testflight', '--app', options[:app], '--build-id', id, '--strict', '--output', 'json')
  exit($?.exitstatus || 1)
end
