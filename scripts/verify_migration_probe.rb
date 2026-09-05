#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"

module MigrationProbe
  def self.verify!(expected, actual, token:, pid:, store_path:)
    raise "Wrong launch token" unless actual.fetch("token") == token
    raise "Wrong process" unless actual.fetch("pid").to_s == pid.to_s
    # CoreSimulator may expose /private/var as /var. Resolve the actual live file.
    raise "Wrong persistent store" unless File.realpath(actual.fetch("store_path")) == File.realpath(store_path)
    expected.each do |key, value|
      raise "Retained user field changed: #{key}" unless actual.fetch(key) == value
    end
    true
  end
end

if $PROGRAM_NAME == __FILE__
  expected_path, marker_path, token, pid, store_path = ARGV
  abort "Usage: verify_migration_probe.rb EXPECTED MARKER TOKEN PID STORE" unless store_path
  begin
    MigrationProbe.verify!(JSON.parse(File.read(expected_path)), JSON.parse(File.read(marker_path)),
                           token: token, pid: pid, store_path: store_path)
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
