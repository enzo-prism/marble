#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"

directory, sha, app, version, build, id, ipa = ARGV
abort "Usage: write_upload_receipt.rb DIRECTORY SHA APP VERSION BUILD BUILD_ID IPA" unless ipa
abort "Invalid source SHA" unless sha.match?(/\A[0-9a-f]{40,64}\z/)
FileUtils.mkdir_p(directory)
run = ENV["GITHUB_RUN_ID"]
attempt = ENV["GITHUB_RUN_ATTEMPT"]
receipt = {
  schema_version: 1, git_sha: sha, app_id: app, marketing_version: version,
  build_number: build, build_id: id, ipa_sha256: Digest::SHA256.file(ipa).hexdigest,
  uploaded_at: Time.now.utc.iso8601,
  archive_identity: run ? "github:#{ENV.fetch('GITHUB_REPOSITORY')}:#{run}:#{attempt}" : "local:#{sha}:#{build}",
  github_repository: ENV["GITHUB_REPOSITORY"], github_run_id: run, github_run_attempt: attempt
}
path = File.join(directory, "upload-#{build}-#{sha}.json")
File.open(path, "wx", 0o600) do |file|
  file.write(JSON.pretty_generate(receipt) + "\n")
  file.flush
  file.fsync
end
File.chmod(0o400, path)
abort "Receipt readback failed" unless JSON.parse(File.read(path))["ipa_sha256"] == receipt[:ipa_sha256]
puts "Verified upload receipt: #{path}"
