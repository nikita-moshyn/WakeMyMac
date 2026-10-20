# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"

module HomebrewRelease
  # The universal binary targets macOS 14.7. Homebrew can use these bottles
  # on Sonoma and newer, on either CPU, without relocating the executable.
  BOTTLE_TAGS = %w[arm64_sonoma sonoma].freeze

  def self.next_rebuild(version, previous_formula)
    return 0 unless previous_formula

    previous = File.read(previous_formula)
    previous_version = previous[/^  version "([^"]+)"$/, 1]
    raise ArgumentError, "The previous formula must specify its version" unless previous_version

    comparison = version.split(".").map(&:to_i) <=> previous_version.split(".").map(&:to_i)
    raise ArgumentError, "Refusing to downgrade the tap to an older release" if comparison.negative?
    return 0 unless comparison.zero? && previous.include?("  bottle do\n")

    previous[/^    rebuild (\d+)$/, 1].to_i + 1
  end

  def self.generate(version:, repository:, archive:, output:, bottle_json: nil, previous_formula: nil)
    raise ArgumentError, "Expected a version such as 2.1.0" unless /\A\d+\.\d+\.\d+\z/.match?(version)
    unless /\A[\w.-]+\/[\w.-]+\z/.match?(repository)
      raise ArgumentError, "Expected a GitHub owner/repository"
    end

    root_url = "https://github.com/#{repository}/releases/download/v#{version}"
    bottle_block = ""
    rebuild = next_rebuild(version, previous_formula)
    archive_checksum = Digest::SHA256.file(archive).hexdigest
    if previous_formula
      previous = File.read(previous_formula)
      if previous[/^  version "([^"]+)"$/, 1] == version &&
         previous[/^  sha256 "([^"]+)"$/, 1] != archive_checksum
        raise ArgumentError, "Existing release archive does not match the formula checksum"
      end
    end

    if bottle_json
      metadata_path = Pathname(bottle_json)
      metadata = JSON.parse(metadata_path.read).values.fetch(0)
      unless metadata.fetch("formula").fetch("pkg_version") == version
        raise ArgumentError, "Bottle version does not match the release"
      end

      bottle = metadata.fetch("bottle")
      rebuild = bottle.fetch("rebuild")
      unless rebuild.is_a?(Integer) && rebuild >= 0
        raise ArgumentError, "Expected a nonnegative bottle rebuild number"
      end
      raise ArgumentError, "Expected one universal bottle" unless bottle.fetch("tags").size == 1

      tag = bottle.fetch("tags").values.fetch(0)
      unless tag.fetch("cellar", bottle["cellar"]) == "any_skip_relocation"
        raise ArgumentError, "The bottle must install without relocation or developer tools"
      end

      filename = tag.fetch("local_filename")
      raise ArgumentError, "Expected a bottle filename" unless File.basename(filename) == filename

      bottle_path = metadata_path.dirname/filename
      checksum = Digest::SHA256.file(bottle_path).hexdigest
      raise ArgumentError, "Bottle checksum does not match its metadata" unless tag.fetch("sha256") == checksum

      # Both files contain the same universal executable. Keep explicit macOS
      # tags rather than advertising an `all` bottle that could match Linux.
      suffix = rebuild.positive? ? ".#{rebuild}" : ""
      BOTTLE_TAGS.each do |bottle_tag|
        destination = metadata_path.dirname/"wakemymac-#{version}.#{bottle_tag}.bottle#{suffix}.tar.gz"
        FileUtils.cp(bottle_path, destination) unless bottle_path == destination
      end

      checksums = BOTTLE_TAGS.map do |bottle_tag|
        "    sha256 cellar: :any_skip_relocation, #{bottle_tag}: \"#{checksum}\""
      end
      bottle_block = [
        "", "  bottle do", "    root_url \"#{root_url}\"",
        ("    rebuild #{rebuild}" if rebuild.positive?),
        *checksums, "  end", ""
      ].compact.join("\n")
    elsif rebuild.positive?
      bottle_block = ["", "  bottle do", "    rebuild #{rebuild}", "  end", ""].join("\n")
    end

    formula = <<~RUBY
      class Wakemymac < Formula
        desc "Prevent Mac from sleeping with configurable wake sessions"
        homepage "https://github.com/#{repository}"
        url "#{root_url}/WakeMyMac_#{version}.tar.gz"
        version "#{version}"
        sha256 "#{archive_checksum}"
        license "Apache-2.0"
      #{bottle_block}
        depends_on :macos

        def install
          bin.install "WakeMyMac_universal" => "wake"
        end

        test do
          system "\#{bin}/wake", "--version"
        end
      end
    RUBY

    output_path = Pathname(output)
    output_path.dirname.mkpath
    output_path.write(formula)
  end
end

if $PROGRAM_NAME == __FILE__
  options = { repository: "nikita-moshyn/WakeMyMac" }
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby scripts/homebrew-release.rb [options]"
    parser.on("--version VERSION") { |value| options[:version] = value }
    parser.on("--repository OWNER/REPOSITORY") { |value| options[:repository] = value }
    parser.on("--archive PATH") { |value| options[:archive] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
    parser.on("--bottle-json PATH") { |value| options[:bottle_json] = value }
    parser.on("--previous-formula PATH") { |value| options[:previous_formula] = value }
  end.parse!

  HomebrewRelease.generate(**options)
end
