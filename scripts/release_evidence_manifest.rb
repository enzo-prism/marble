#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "find"
require "json"
require "pathname"
require "time"

CONTROL_DIRECTORY = ".evidence"
MANIFEST_FILENAME = "manifest.json"
CHECKSUM_FILENAME = "checksums.sha256"
REQUIRED_RELEASE_GATES = %w[unit snapshot ui accessibility migration].freeze

def usage!
  warn "Usage: release_evidence_manifest.rb generate RUN_DIR | verify MANIFEST"
  exit 1
end

def digest_path(path)
  if path.symlink?
    contents = path.readlink.to_s
    return {
      "kind" => "symlink",
      "digest_algorithm" => "sha256-symlink-v1",
      "sha256" => Digest::SHA256.hexdigest(contents),
      "size_bytes" => contents.bytesize
    }
  end

  if path.file?
    return {
      "kind" => "file",
      "digest_algorithm" => "sha256",
      "sha256" => Digest::SHA256.file(path.to_s).hexdigest,
      "size_bytes" => path.size
    }
  end

  digest = Digest::SHA256.new
  size = 0
  entries = []
  Find.find(path.to_s) do |candidate|
    candidate_path = Pathname.new(candidate)
    next if candidate_path == path

    relative = candidate_path.relative_path_from(path).to_s
    entries << [relative, candidate_path]
  end
  entries.sort_by!(&:first)
  entries.each do |relative, candidate|
    if candidate.symlink?
      contents = candidate.readlink.to_s
      entry_digest = Digest::SHA256.hexdigest(contents)
      entry_kind = "symlink"
      entry_size = contents.bytesize
    elsif candidate.directory?
      entry_digest = "-"
      entry_kind = "directory"
      entry_size = 0
    else
      entry_digest = Digest::SHA256.file(candidate.to_s).hexdigest
      entry_kind = "file"
      entry_size = candidate.size
    end
    digest << relative << "\0" << entry_kind << "\0" << entry_digest << "\0"
    size += entry_size
  end
  {
    "kind" => "directory",
    "digest_algorithm" => "sha256-tree-v1",
    "sha256" => digest.hexdigest,
    "size_bytes" => size,
    "entry_count" => entries.length
  }
end

def artifact_paths(run_dir)
  paths = []
  Find.find(run_dir.to_s) do |candidate|
    path = Pathname.new(candidate)
    relative = path.relative_path_from(run_dir).to_s
    if relative == CONTROL_DIRECTORY || relative.start_with?("#{CONTROL_DIRECTORY}/")
      Find.prune if path.directory?
      next
    end
    next if relative == "." || [MANIFEST_FILENAME, CHECKSUM_FILENAME].include?(relative)

    if path.directory? && path.basename.to_s.end_with?(".xcresult")
      paths << path
      Find.prune
    elsif path.file? || path.symlink?
      paths << path
    end
  end
  paths.sort_by { |path| path.relative_path_from(run_dir).to_s }
end

def generate(run_dir)
  control = run_dir.join(CONTROL_DIRECTORY)
  metadata_path = control.join("run.json")
  abort "Missing run metadata: #{metadata_path}" unless metadata_path.file?
  manifest_path = run_dir.join(MANIFEST_FILENAME)
  checksum_path = run_dir.join(CHECKSUM_FILENAME)
  abort "Refusing to overwrite: #{manifest_path}" if manifest_path.exist?
  abort "Refusing to overwrite: #{checksum_path}" if checksum_path.exist?

  metadata = JSON.parse(metadata_path.read)
  gate_records = Dir[control.join("gates/*.json").to_s].sort.map { |path| JSON.parse(File.read(path)) }
  abort "No gate records found in #{control.join("gates")}" if gate_records.empty?
  records_by_name = gate_records.to_h { |gate| [gate.fetch("name"), gate] }
  requested_gates = metadata.fetch("requested_gates")
  gates = requested_gates.map do |name|
    records_by_name.fetch(name) { abort "Missing gate record for #{name}" }
  end

  artifacts = artifact_paths(run_dir).map do |path|
    { "path" => path.relative_path_from(run_dir).to_s }.merge(digest_path(path))
  end
  overall_status = gates.all? { |gate| gate.fetch("status") == "passed" } ? "passed" : "failed"
  manifest = {
    "schema_version" => 1,
    "generated_at" => Time.now.utc.iso8601,
    "candidate" => {
      "git_sha" => metadata.fetch("git_sha"),
      "marketing_version" => metadata.fetch("marketing_version"),
      "build_number" => metadata.fetch("build_number")
    },
    "run" => {
      "id" => metadata.fetch("run_id"),
      "started_at" => metadata.fetch("started_at"),
      "completed_at" => Time.now.utc.iso8601,
      "overall_status" => overall_status
    },
    "coverage" => {
      "required_release_gates" => REQUIRED_RELEASE_GATES,
      "requested_gates" => requested_gates,
      "complete_release_gate_set" => requested_gates.sort == REQUIRED_RELEASE_GATES.sort
    },
    "gates" => gates,
    "artifacts" => artifacts
  }

  manifest_path.write(JSON.pretty_generate(manifest) + "\n")
  checksum_path.write(artifacts.map { |artifact| "#{artifact.fetch("sha256")}  #{artifact.fetch("path")}" }.join("\n") + "\n")
  puts "Generated #{manifest_path} (#{overall_status}; #{artifacts.length} artifacts)"
end

def verify(manifest_path)
  abort "Manifest not found: #{manifest_path}" unless manifest_path.file?
  run_dir = manifest_path.dirname
  manifest = JSON.parse(manifest_path.read)
  abort "Unsupported manifest schema" unless manifest.fetch("schema_version") == 1

  errors = []
  manifest.fetch("artifacts").each do |artifact|
    relative_path = Pathname.new(artifact.fetch("path"))
    if relative_path.absolute? || relative_path.each_filename.any? { |part| part == ".." }
      errors << "unsafe artifact path: #{artifact.fetch("path")}"
      next
    end
    path = run_dir.join(relative_path)
    unless path.exist? || path.symlink?
      errors << "missing: #{artifact.fetch("path")}"
      next
    end
    actual = digest_path(path)
    %w[kind digest_algorithm sha256 size_bytes entry_count].each do |key|
      next unless artifact.key?(key)
      errors << "#{artifact.fetch("path")}: #{key} changed" unless actual[key] == artifact[key]
    end
  end

  expected_paths = manifest.fetch("artifacts").map { |artifact| artifact.fetch("path") }.sort
  actual_paths = artifact_paths(run_dir).map { |path| path.relative_path_from(run_dir).to_s }.sort
  (actual_paths - expected_paths).each { |path| errors << "untracked artifact: #{path}" }

  checksum_path = run_dir.join(CHECKSUM_FILENAME)
  expected_checksums = manifest.fetch("artifacts").map do |artifact|
    "#{artifact.fetch("sha256")}  #{artifact.fetch("path")}"
  end.join("\n") + "\n"
  if !checksum_path.file?
    errors << "missing: #{CHECKSUM_FILENAME}"
  elsif checksum_path.read != expected_checksums
    errors << "#{CHECKSUM_FILENAME}: content does not match manifest"
  end

  unless errors.empty?
    warn "Release evidence verification failed:"
    errors.each { |error| warn "  - #{error}" }
    exit 1
  end
  puts "Verified #{manifest_path} (#{expected_paths.length} artifacts)"
end

command = ARGV.shift
target = ARGV.shift
usage! unless target && ARGV.empty?

case command
when "generate"
  generate(Pathname.new(target).expand_path)
when "verify"
  verify(Pathname.new(target).expand_path)
else
  usage!
end
