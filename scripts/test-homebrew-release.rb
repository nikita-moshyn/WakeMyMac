# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "homebrew-release"

class HomebrewReleaseTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("wakemymac-release-test")
    @archive = File.join(@directory, "WakeMyMac_2.1.0.tar.gz")
    File.binwrite(@archive, "release archive fixture")
    @bottle_path = File.join(@directory, "wakemymac--2.1.0.arm64_sequoia.bottle.tar.gz")
    File.binwrite(@bottle_path, "universal bottle fixture")
    @metadata = {
      "release/build/wakemymac" => {
        "formula" => { "pkg_version" => "2.1.0" },
        "bottle" => {
          "cellar" => "any_skip_relocation",
          "rebuild" => 0,
          "tags" => {
            "arm64_sequoia" => {
              "local_filename" => File.basename(@bottle_path),
              "sha256" => Digest::SHA256.file(@bottle_path).hexdigest
            }
          }
        }
      }
    }
    @metadata_path = File.join(@directory, "bottle.json")
    @output = File.join(@directory, "Formula/wakemymac.rb")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def generate(with_bottle: true)
    File.write(@metadata_path, JSON.generate(@metadata))
    HomebrewRelease.generate(
      version: "2.1.0", repository: "nikita-moshyn/WakeMyMac",
      archive: @archive, output: @output,
      bottle_json: with_bottle ? @metadata_path : nil
    )
    File.read(@output)
  end

  def assets_manifest(*names)
    manifest = File.join(@directory, "release-assets.json")
    File.write(manifest, JSON.generate("assets" => names.map { |name| { "name" => name } }))
    manifest
  end

  def test_generates_downloadable_bottles_for_both_architectures
    formula = generate
    checksum = Digest::SHA256.file(@bottle_path).hexdigest
    %w[arm64_sonoma sonoma].each do |tag|
      asset = File.join(@directory, "wakemymac-2.1.0.#{tag}.bottle.tar.gz")
      assert_equal checksum, Digest::SHA256.file(asset).hexdigest
      assert_includes formula, "sha256 cellar: :any_skip_relocation, #{tag}: \"#{checksum}\""
    end
    assert_includes formula, 'root_url "https://github.com/nikita-moshyn/WakeMyMac/releases/download/v2.1.0"'
    assert_includes formula, 'system "#{bin}/wake", "--version"'
    refute_includes formula, "all:"
  end

  def test_rejects_a_bottle_that_needs_developer_tools_for_relocation
    @metadata.values.first["bottle"]["cellar"] = "any"
    assert_raises(ArgumentError) { generate }
    refute File.exist?(@output)
  end

  def test_rejects_a_corrupted_bottle_before_publishing_the_formula
    File.binwrite(@bottle_path, "changed bottle")
    assert_raises(ArgumentError) { generate }
    refute File.exist?(@output)
  end

  def test_rejects_bottles_from_another_release
    @metadata.values.first["formula"]["pkg_version"] = "2.0.0"
    assert_raises(ArgumentError) { generate }
  end

  def test_generates_the_initial_formula_without_referencing_unpublished_bottles
    formula = generate(with_bottle: false)
    assert_includes formula, Digest::SHA256.file(@archive).hexdigest
    refute_includes formula, "bottle do"
  end

  def test_rebuilds_get_new_asset_names_without_replacing_published_bottles
    @metadata.values.first["bottle"]["rebuild"] = 1
    formula = generate
    assert_includes formula, "    rebuild 1\n"
    assert File.exist?(File.join(@directory, "wakemymac-2.1.0.arm64_sonoma.bottle.1.tar.gz"))
    assert File.exist?(File.join(@directory, "wakemymac-2.1.0.sonoma.bottle.1.tar.gz"))
    assert_equal 2, HomebrewRelease.next_rebuild("2.1.0", @output)
    assert_equal 0, HomebrewRelease.next_rebuild("2.2.0", @output)
    assert_raises(ArgumentError) { HomebrewRelease.next_rebuild("2.0.0", @output) }
  end

  def test_the_first_bottle_repair_starts_at_rebuild_zero
    generate(with_bottle: false)
    assert_equal 0, HomebrewRelease.next_rebuild("2.1.0", @output)
    generate
    assert_equal 1, HomebrewRelease.next_rebuild("2.1.0", @output)
  end

  def test_preserves_the_existing_release_checksum_during_a_repair
    generate(with_bottle: false)
    original_formula = File.read(@output)
    File.binwrite(@archive, "changed release archive")
    assert_raises(ArgumentError) do
      HomebrewRelease.generate(
        version: "2.1.0", repository: "nikita-moshyn/WakeMyMac",
        archive: @archive, output: @output, previous_formula: @output
      )
    end
    assert_equal original_formula, File.read(@output)
  end

  def test_passes_the_next_rebuild_to_homebrew_without_reusing_old_bottles
    generate
    HomebrewRelease.generate(
      version: "2.1.0", repository: "nikita-moshyn/WakeMyMac",
      archive: @archive, output: @output, previous_formula: @output
    )
    formula = File.read(@output)
    assert_includes formula, "    rebuild 1\n"
    refute_includes formula, "sha256 cellar:"
  end

  def test_retries_an_upload_that_succeeded_before_the_formula_push
    generate(with_bottle: false)
    assets = assets_manifest(
      "WakeMyMac_2.1.0.tar.gz",
      "wakemymac-2.1.0.arm64_sonoma.bottle.tar.gz",
      "wakemymac-2.1.0.sonoma.bottle.tar.gz"
    )
    HomebrewRelease.generate(
      version: "2.1.0", repository: "nikita-moshyn/WakeMyMac",
      archive: @archive, output: @output, previous_formula: @output, release_assets: assets
    )
    assert_includes File.read(@output), "    rebuild 1\n"
  end

  def test_skips_a_rebuild_when_only_one_platform_was_uploaded
    assets = assets_manifest("wakemymac-2.1.0.arm64_sonoma.bottle.3.tar.gz")
    assert_equal 4, HomebrewRelease.next_rebuild("2.1.0", nil, release_assets: assets)
  end

  def test_published_assets_cannot_lower_the_formula_rebuild
    @metadata.values.first["bottle"]["rebuild"] = 5
    generate
    assets = assets_manifest("wakemymac-2.1.0.sonoma.bottle.1.tar.gz")
    assert_equal 6, HomebrewRelease.next_rebuild("2.1.0", @output, release_assets: assets)
  end

  def test_ignores_other_releases_and_non_bottle_assets
    assets = assets_manifest(
      "WakeMyMac_2.1.0.tar.gz", "wakemymac-2.0.0.sonoma.bottle.9.tar.gz",
      "wakemymac--2.1.0.arm64_sequoia.bottle.tar.gz"
    )
    assert_equal 0, HomebrewRelease.next_rebuild("2.1.0", nil, release_assets: assets)
  end
end
