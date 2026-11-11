#!/usr/bin/env ruby
# Validate the metadata Apple actually extracted, before uploading the binary.
# This format is checked against the pinned Xcode 27.0 SDK; fail closed on changes.
require 'json'

module MarbleIntentAuthentication
  REQUIRED_ACTIONS = %w[
    LogSetIntent LogLastSetAgainIntent CorrectLoggedSetIntent FindWorkoutsIntent
    StartWorkoutIntent FinishWorkoutIntent OpenWorkoutSessionIntent OpenExerciseIntent
    ReviewRepeatedWorkoutIntent ReviewWorkoutTextIntent ReviewWorkoutFileIntent
  ].freeze

  def self.verify(metadata)
    actions = metadata.fetch('actions')
    REQUIRED_ACTIONS.each do |name|
      action = actions.fetch(name)
      unless action['isAuthPolExplicit'] == true && [1, 2].include?(action['authenticationPolicy'])
        raise "#{name} must explicitly require authentication in extracted App Intents metadata"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: verify_intent_authentication.rb APP_BUNDLE' unless ARGV.length == 1
  begin
    path = File.join(ARGV.fetch(0), 'Metadata.appintents', 'extract.actionsdata')
    MarbleIntentAuthentication.verify(JSON.parse(File.read(path)))
    puts 'Verified authentication for private workout actions in extracted metadata.'
  rescue StandardError => error
    abort "Intent authentication verification failed: #{error.message}"
  end
end
