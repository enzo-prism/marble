# frozen_string_literal: true
require "minitest/autorun"
require "open3"
require "json"
require "fileutils"
require "tmpdir"
require "yaml"

class ReleaseEvidenceAssembleTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SHARDS = File.join(ROOT, "scripts/release_ui_shards.sh")
  EVIDENCE = File.join(ROOT, "scripts/release_evidence.sh")
  WORKFLOW = File.join(ROOT, ".github/workflows/release-checks.yml")

  def test_ui_shards_partition_every_ui_class_except_accessibility_audit
    on_disk = Dir[File.join(ROOT, "Tests/UI/*UITests.swift")].map do |path|
      File.basename(path, ".swift")
    end - %w[AccessibilityAuditUITests]
    shards = (1..3).map { |shard| shard_classes(shard) }
    assert_equal on_disk.sort, shards.flatten.sort
    assert_equal on_disk.length, shards.flatten.uniq.length
    refute_includes shards.flatten, "AccessibilityAuditUITests"
    assert shards[0].include?("JournalFlowUITests")
    assert shards[0].include?("KeyboardLayoutUITests")
  end

  def test_assemble_builds_one_five_gate_manifest_from_parallel_fragments
    Dir.mktmpdir("marble-assemble-") do |dir|
      fragments = File.join(dir, "fragments")
      sha, build, version = candidate_identity
      %w[unit snapshot accessibility migration].each do |gate|
        write_fragment(fragments, "release-evidence-#{gate}", sha, build, version, gate)
      end
      (1..3).each do |shard|
        write_ui_shard_fragment(fragments, shard, sha, build, version)
      end

      run_dir = assemble(dir, fragments)
      status = finalize(dir, run_dir)
      assert status.success?, status_error(status)
      manifest = JSON.parse(File.read(File.join(run_dir, "manifest.json")))
      assert_equal %w[unit snapshot ui accessibility migration], manifest.fetch("gates").map { |gate| gate.fetch("name") }
      assert manifest.dig("coverage", "complete_release_gate_set")
      assert_equal "passed", manifest.dig("run", "overall_status")
      assert File.directory?(File.join(run_dir, "ui/shard-1.xcresult"))
      assert File.directory?(File.join(run_dir, "ui/shard-2.xcresult"))
      assert File.directory?(File.join(run_dir, "ui/shard-3.xcresult"))
    end
  end

  def test_assemble_fails_ui_gate_when_a_shard_is_missing
    Dir.mktmpdir("marble-assemble-missing-") do |dir|
      fragments = File.join(dir, "fragments")
      sha, build, version = candidate_identity
      %w[unit snapshot accessibility migration].each do |gate|
        write_fragment(fragments, "release-evidence-#{gate}", sha, build, version, gate)
      end
      [1, 3].each do |shard|
        write_ui_shard_fragment(fragments, shard, sha, build, version)
      end

      run_dir = assemble(dir, fragments)
      status = finalize(dir, run_dir)
      refute status.success?
      manifest = JSON.parse(File.read(File.join(run_dir, "manifest.json")))
      ui = manifest.fetch("gates").find { |gate| gate.fetch("name") == "ui" }
      assert_equal "failed", ui.fetch("status")
    end
  end

  def test_release_checks_jobs_stay_parallel_and_under_two_hours
    workflow = YAML.load_file(WORKFLOW)
    jobs = workflow.fetch("jobs")
    %w[unit snapshot ui accessibility migration evidence].each do |name|
      assert jobs.key?(name), "missing job #{name}"
    end
    jobs.each do |name, job|
      cap = Integer(job.fetch("timeout-minutes"))
      step_sum = job.fetch("steps").sum { |step| Integer(step["timeout-minutes"] || 0) }
      assert_operator cap, :<=, 120, "#{name} job cap #{cap} is over 120"
      assert_operator cap, :>=, step_sum, "#{name} job #{cap} is below step sum #{step_sum}"
      upload = job.fetch("steps").reverse.find { |step| step["uses"].to_s.include?("upload-artifact") }
      assert_equal "always()", upload.fetch("if"), "#{name} upload must always run"
      assert_equal 10, Integer(upload.fetch("timeout-minutes"))
    end
    assert_equal 100, Integer(jobs.fetch("ui").fetch("timeout-minutes"))
    assert_equal 120, Integer(jobs.fetch("accessibility").fetch("timeout-minutes"))
    assert_equal 80, Integer(jobs.fetch("migration").fetch("timeout-minutes"))
    evidence = jobs.fetch("evidence")
    assert_equal %w[unit snapshot ui accessibility migration], evidence.fetch("needs")
    assert_equal "always()", evidence.fetch("if")
    upload = evidence.fetch("steps").find { |step| step["name"] == "Preserve candidate evidence" }
    assert_equal "release-evidence", upload.dig("with", "name")
    assert_equal %w[1 2 3], jobs.fetch("ui").dig("strategy", "matrix", "shard")
  end

  private

  def shard_classes(shard)
    output, error, status = Open3.capture3("bash", SHARDS, "--classes", shard.to_s)
    assert status.success?, error
    output.lines.map(&:strip).reject(&:empty?)
  end

  def candidate_identity
    sha = Open3.capture2("git", "-C", ROOT, "rev-parse", "HEAD").first.strip
    project = File.read(File.join(ROOT, "marble.xcodeproj/project.pbxproj"))
    build = project.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    version = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    raise "ambiguous identity" unless build.length == 1 && version.length == 1
    [sha, build.first, version.first]
  end

  def write_run(run, sha, build, version, gates)
    FileUtils.mkdir_p(File.join(run, ".evidence/gates"))
    File.write(
      File.join(run, ".evidence/run.json"),
      JSON.generate(
        schema_version: 1,
        started_at: "2026-11-17T19:00:00Z",
        git_sha: sha,
        build_number: build,
        marketing_version: version,
        run_id: File.basename(run),
        clean_run: true,
        requested_gates: gates
      )
    )
  end

  def write_gate(run, name, command: "make #{name}")
    FileUtils.mkdir_p(File.join(run, name))
    File.write(File.join(run, name, "command.log"), "#{name} passed\n")
    unless name == "migration"
      xcresult = File.join(run, name, name == "snapshot" ? "00-snapshots.xcresult" : "Marble.xcresult")
      FileUtils.mkdir_p(xcresult)
      File.write(File.join(xcresult, "Info.plist"), "#{name}\n")
    end
    File.write(
      File.join(run, ".evidence/gates/#{name}.json"),
      JSON.generate(
        name: name,
        status: "passed",
        exit_code: 0,
        started_at: "2026-11-17T19:00:00Z",
        completed_at: "2026-11-17T19:10:00Z",
        command: command,
        reason: nil
      )
    )
  end

  def write_fragment(root, artifact, sha, build, version, gate)
    run = File.join(root, artifact, sha, "build-#{build}", "run-#{gate}")
    write_run(run, sha, build, version, [gate])
    write_gate(run, gate)
  end

  def write_ui_shard_fragment(root, shard, sha, build, version)
    run = File.join(root, "release-evidence-ui-#{shard}", sha, "build-#{build}", "run-ui-#{shard}")
    write_run(run, sha, build, version, %w[ui])
    FileUtils.mkdir_p(File.join(run, "ui"))
    xcresult = File.join(run, "ui", "shard-#{shard}.xcresult")
    FileUtils.mkdir_p(xcresult)
    File.write(File.join(xcresult, "Info.plist"), "ui-#{shard}\n")
    File.write(File.join(run, "ui/command.log"), "ui shard #{shard} passed\n")
    FileUtils.mkdir_p(File.join(run, ".evidence/gates"))
    File.write(
      File.join(run, ".evidence/gates/ui.json"),
      JSON.generate(
        name: "ui",
        status: "passed",
        exit_code: 0,
        started_at: "2026-11-17T19:20:00Z",
        completed_at: "2026-11-17T20:20:00Z",
        command: "make ui shard #{shard}",
        reason: nil
      )
    )
  end

  def assemble(dir, fragments)
    env = evidence_env(dir)
    output, error, status = Open3.capture3(env, "bash", EVIDENCE, "assemble", fragments)
    assert status.success?, "#{output}\n#{error}"
    match = output.lines.grep(/Assembled release evidence run: /).last
    refute_nil match, output
    match.split(": ", 2).last.strip
  end

  def finalize(dir, run_dir)
    env = evidence_env(dir)
    env["RELEASE_EVIDENCE_CONTINUE_DIR"] = run_dir
    output, error, status = Open3.capture3(env, "bash", EVIDENCE, "finalize")
    @last_finalize = "#{output}\n#{error}"
    status
  end

  def status_error(_status)
    @last_finalize
  end

  def evidence_env(dir)
    {
      "RELEASE_EVIDENCE_ROOT" => File.join(dir, "assembled"),
      "RELEASE_EVIDENCE_ALLOW_DIRTY" => "1",
      "GITHUB_ENV" => File.join(dir, "github.env")
    }
  end
end
