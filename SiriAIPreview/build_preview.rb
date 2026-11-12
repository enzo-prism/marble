#!/usr/bin/env ruby
# Run with Xcode 27.3+ selected. Generates an isolated project next to the normal
# one, so source paths stay identical and public archives cannot inherit flags.
require 'fileutils'
require 'json'
require 'open3'
require 'xcodeproj'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
version, status = Open3.capture2('xcodebuild', '-version')
abort 'Xcode is unavailable.' unless status.success?
match = version.match(/Xcode (\d+)\.(\d+)/)
abort 'Siri preview requires Xcode 27.3 or newer. The normal release configuration is unchanged.' unless match && ([match[1].to_i, match[2].to_i] <=> [27, 3]) >= 0
sdk, status = Open3.capture2('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
abort 'Select an iOS 27.3+ SDK before building preview tools.' unless status.success? && Gem::Version.new(sdk.strip) >= Gem::Version.new('27.3')
abort 'Usage: build_preview.rb DEVICE_UDID DERIVED_DATA_PATH [xcodebuild signing settings...]' if ARGV.length < 2
udid, derived, *settings = ARGV
abort 'Preview requires a physical device UDID.' unless udid.match?(/\A[0-9A-Fa-f-]+\z/)
abort 'Derived data must be an absolute path.' unless derived.start_with?('/')

# Validate Apple's restricted app-skill format before asking Xcode to compile it.
skills = Dir.glob('SiriAIPreview/Skills.skillsbundle/Skills/*/SKILL.md')
abort 'No app skills found.' if skills.empty?
skills.each do |path|
  text = File.read(path)
  frontmatter, body = text.match(/\A---\n(.*?)\n---\n(.*)\z/m)&.captures
  abort "Invalid frontmatter: #{path}" unless frontmatter
  name = frontmatter[/^name: (.+)$/, 1]
  description = frontmatter[/^description: (.+)$/, 1]
  abort "Invalid skill name: #{path}" unless name && name.length <= 64 && name.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) && name == File.basename(File.dirname(path))
  abort "Invalid description: #{path}" unless description && !description.empty? && description.length <= 1024
  abort "Skill too long: #{path}" unless body.length <= 10_000
  abort "Unsupported skill metadata: #{path}" unless frontmatter.lines.length == 2
end

generated = '.MarbleSiriPreview.xcodeproj'
FileUtils.rm_rf(generated)
FileUtils.cp_r('marble.xcodeproj', generated)
Dir.glob("#{generated}/**/*.xcscheme").each do |path|
  File.write(path, File.read(path).gsub('container:marble.xcodeproj', "container:#{generated}"))
end
Dir.glob("#{generated}/**/*.xctestplan").each do |path|
  File.write(path, File.read(path).gsub('container:marble.xcodeproj', "container:#{generated}"))
end
project = Xcodeproj::Project.open(generated)
app = project.targets.find { |target| target.name == 'marble' }
preview = project.main_group.new_group('Siri Preview')
ref = preview.new_file('SiriAIPreview/Skills.skillsbundle')
# Let the selected preview SDK infer its skills-bundle type from the extension.
# Do not mark this as a generic folder, which would merely copy raw Markdown.
ref.last_known_file_type = nil
app.resources_build_phase.add_file_reference(ref)
app.build_configurations.each do |config|
  next unless config.name == 'Debug'
  flags = config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] || '$(inherited) DEBUG'
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = "#{flags} SIRI_AI_PREVIEW"
end
project.save

log = File.join(derived, 'siri-preview-build.log')
FileUtils.mkdir_p(derived)
command = ['xcodebuild', 'build', '-project', generated, '-scheme', 'marble', '-configuration', 'Debug',
  '-destination', "platform=iOS,id=#{udid}", '-derivedDataPath', derived, *settings]
File.open(log, 'w') do |output|
  pid = Process.spawn(*command, out: output, err: [:child, :out])
  Process.wait(pid)
  abort "Preview build failed. Inspect #{log}" unless $?.success?
end
compiled = File.read(log).match?(/(?:CompileSkills|CompileAppSkills|Compile.*Skills\.skillsbundle)/)
abort "Build did not prove skill compilation. Inspect Xcode's resource type and #{log}; raw copied Markdown is not acceptance." unless compiled
puts "Development preview built. Build log: #{log}"
puts 'Run Siri Integration Advisor and the conversation scenarios on a supported iOS 27.3+ device. This script does not upload or submit a public build.'
