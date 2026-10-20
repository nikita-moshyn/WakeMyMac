# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"
require_relative "homebrew-release"

class ReleaseWorkflowTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ARCHIVE = "WakeMyMac_2.1.0.tar.gz"

  FAKE_GH = <<~'RUBY'
    #!/usr/bin/env ruby
    require "digest"
    require "json"
    state_path = ENV.fetch("FAKE_GH_STATE")
    state = JSON.parse(File.read(state_path))
    state["events"] << ARGV
    at_exit { File.write(state_path, JSON.generate(state)) }
    abort "unsupported command" unless ARGV[0] == "release"
    release = state["release"]
    case ARGV[1]
    when "view"
      abort state["view_error"] if state["view_error"]
      abort "release not found" unless release
      puts JSON.generate(release)
    when "create"
      abort "release already exists" if release
      abort "release must start as draft" unless ARGV.include?("--draft")
      state["release"] = { "assets" => [], "isDraft" => true }
    when "delete-asset"
      abort "release not found" unless release
      release["assets"].reject! { |asset| asset["name"] == ARGV[3] }
    when "upload"
      abort "release not found" unless release
      files = []
      index = 3
      while index < ARGV.length
        if ARGV[index] == "--repo"
          index += 2
        elsif ARGV[index].start_with?("--")
          abort "unsupported upload flag: #{ARGV[index]}"
        else
          files << ARGV[index]
          index += 1
        end
      end
      files.each do |path|
        name = File.basename(path)
        abort "asset already exists: #{name}" if release["assets"].any? { |asset| asset["name"] == name }
        state["upload_count"] = state.fetch("upload_count", 0) + 1
        abort "simulated upload failure" if state["upload_count"] == state["fail_upload_at"]
        release["assets"] << {
          "name" => name, "state" => "uploaded", "size" => File.size(path),
          "digest" => "sha256:#{Digest::SHA256.file(path).hexdigest}"
        }
      end
    when "edit"
      abort "release not found" unless release
      abort "expected publication" unless ARGV.include?("--draft=false")
      release["isDraft"] = false
    else
      abort "unsupported release command"
    end
  RUBY

  def setup
    @directory = Dir.mktmpdir("wakemymac-workflow-test")
    @state_path = File.join(@directory, "github.json")
    @manifest = File.join(@directory, "release-assets.json")
    @output_path = File.join(@directory, "github-output")
    FileUtils.ln_s(File.join(ROOT, "scripts"), File.join(@directory, "scripts"))
    FileUtils.mkdir_p(File.join(@directory, "bin"))
    executable = File.join(@directory, "bin/gh")
    File.write(executable, FAKE_GH)
    File.chmod(0o755, executable)
    @environment = {
      "PATH" => "#{File.join(@directory, "bin")}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}",
      "FAKE_GH_STATE" => @state_path,
      "GITHUB_REPOSITORY" => "nikita-moshyn/WakeMyMac", "RELEASE_TAG" => "v2.1.0",
      "VERSION" => "2.1.0", "GITHUB_OUTPUT" => @output_path
    }
    FileUtils.mkdir_p(File.join(@directory, "release-input"))
    File.write(File.join(@directory, "release-input", ARCHIVE), "release archive")
    reset_release(nil)
    write_bottles
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def state
    JSON.parse(File.read(@state_path))
  end

  def reset_release(release, extra = {})
    File.write(@state_path, JSON.generate({ "release" => release, "events" => [] }.merge(extra)))
  end

  def release(draft:, assets: [])
    { "isDraft" => draft, "assets" => assets }
  end

  def archive_asset
    { "name" => ARCHIVE, "state" => "uploaded", "size" => 15 }
  end

  def write_bottles(rebuild = 0)
    destination = File.join(@directory, "dist")
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
    suffix = rebuild.positive? ? ".#{rebuild}" : ""
    HomebrewRelease::BOTTLE_TAGS.each do |tag|
      File.write(File.join(destination, "wakemymac-2.1.0.#{tag}.bottle#{suffix}.tar.gz"), "bottle")
    end
  end

  def inspect_release(event = "push")
    FileUtils.rm_f(@output_path)
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/release.yml"))
    step = workflow.fetch("jobs").fetch("homebrew").fetch("steps").find do |entry|
      entry["name"] == "Refresh the release state"
    end
    stdout, stderr, status = Open3.capture3(
      @environment.merge("GITHUB_EVENT_NAME" => event), "bash", "-c", step.fetch("run"), chdir: @directory
    )
    if status.success?
      @outputs = File.readlines(@output_path).to_h { |line| line.strip.split("=", 2) }
      # A failed-job rerun retains prepare's original successful outputs.
      @prepare_outputs ||= @outputs.dup
    end
    [stdout, stderr, status]
  end

  def publish
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/release.yml"))
    step = workflow.fetch("jobs").fetch("homebrew").fetch("steps").find do |entry|
      entry["name"] == "Publish the release assets"
    end
    environment = step.fetch("env").to_h do |name, expression|
      context, field = expression.match(/\A\$\{\{\s*(steps\.release|needs\.prepare)\.outputs\.(\w+)\s*\}\}\z/).captures
      outputs = context == "steps.release" ? @outputs : @prepare_outputs
      [name, outputs.fetch(field)]
    end
    Open3.capture3(@environment.merge(environment), "bash", "-c", step.fetch("run"), chdir: @directory)
  end

  def test_new_tag_builds_an_archive_and_publishes_after_all_uploads
    _, stderr, status = inspect_release
    assert status.success?, stderr
    assert_equal "false", @outputs["has_binary"]
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal false, state["release"]["isDraft"]
    assert_equal 3, state["release"]["assets"].size
    assert_equal %w[view create upload upload edit], state["events"].map { |event| event[1] }
  end

  def test_manual_repair_rebuilds_a_draft_that_has_no_archive
    reset_release(release(draft: true))
    _, stderr, status = inspect_release("workflow_dispatch")
    assert status.success?, stderr
    assert_equal "true", @outputs["exists"]
    assert_equal "false", @outputs["has_binary"]
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal false, state["release"]["isDraft"]
    assert_includes state["release"]["assets"].map { |asset| asset["name"] }, ARCHIVE
  end

  def test_existing_archive_is_reused_and_never_deleted
    original = archive_asset
    reset_release(release(draft: false, assets: [original]))
    _, stderr, status = inspect_release
    assert status.success?, stderr
    assert_equal "true", @outputs["has_binary"]
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal original, state["release"]["assets"].find { |asset| asset["name"] == ARCHIVE }
    refute state["events"].any? { |event| event[1] == "delete-asset" }
    assert_equal 1, state["events"].count { |event| event[1] == "upload" }
  end

  def test_archive_detection_requires_the_exact_version
    reset_release(release(draft: true, assets: [{ "name" => "WakeMyMac_2.0.0.tar.gz", "size" => 15 }]))
    _, stderr, status = inspect_release
    assert status.success?, stderr
    assert_equal "false", @outputs["has_binary"]
  end

  def test_a_failed_upload_leaves_the_draft_unpublished_and_can_be_retried
    reset_release(nil, "fail_upload_at" => 3)
    assert inspect_release.last.success?
    _, _, status = publish
    refute status.success?
    assert_equal true, state["release"]["isDraft"]
    refute state["events"].any? { |event| event[1] == "edit" }

    preserved_assets = state["release"]["assets"].dup
    _, stderr, status = inspect_release("workflow_dispatch")
    assert status.success?, stderr
    rebuild = HomebrewRelease.next_rebuild("2.1.0", nil, release_assets: @manifest)
    assert_equal 1, rebuild
    write_bottles(rebuild)
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal false, state["release"]["isDraft"]
    preserved_assets.each { |asset| assert_includes state["release"]["assets"], asset }
  end

  def test_failed_job_rerun_refreshes_a_draft_created_before_the_archive_upload_failed
    reset_release(nil, "fail_upload_at" => 1)
    assert inspect_release.last.success?
    _, _, status = publish
    refute status.success?
    assert_equal true, state["release"]["isDraft"]
    assert_empty state["release"]["assets"]

    _, stderr, status = inspect_release
    assert status.success?, stderr
    assert_equal "false", @prepare_outputs["exists"]
    assert_equal "true", @outputs["exists"]
    assert_equal "false", @outputs["has_binary"]
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal false, state["release"]["isDraft"]
    assert_equal 3, state["release"]["assets"].size
    assert_equal 1, state["events"].count { |event| event[1] == "create" }
  end

  def test_an_incomplete_archive_upload_is_replaced
    reset_release(release(draft: true, assets: [{ "name" => ARCHIVE, "state" => "starter", "size" => 0 }]))
    _, stderr, status = inspect_release
    assert status.success?, stderr
    assert_equal "false", @outputs["has_binary"]
    assert_equal "true", @outputs["replace_incomplete_binary"]
    _, stderr, status = publish
    assert status.success?, stderr
    assert_equal %w[view delete-asset upload upload edit], state["events"].map { |event| event[1] }
  end

  def test_api_errors_are_not_treated_as_missing_releases
    reset_release(nil, "view_error" => "HTTP 503: service unavailable")
    _, stderr, status = inspect_release
    refute status.success?
    assert_includes stderr, "Cannot inspect the release"
    refute File.exist?(@manifest)
  end

  def test_manual_repair_rejects_a_nonexistent_release
    _, stderr, status = inspect_release("workflow_dispatch")
    refute status.success?
    assert_includes stderr, "No existing release found"
    assert_equal ["view"], state["events"].map { |event| event[1] }
  end
end
