# frozen_string_literal: true

require "json"
require "open3"
require "optparse"

module ReleaseState
  def self.inspect_release(tag:, repository:, event_name:, output:)
    raise ArgumentError, "Expected a tag such as v2.1.0" unless /\Av\d+\.\d+\.\d+\z/.match?(tag)
    raise ArgumentError, "Expected a GitHub owner/repository" unless /\A[\w.-]+\/[\w.-]+\z/.match?(repository)
    raise ArgumentError, "Unsupported release event" unless %w[push workflow_dispatch].include?(event_name)

    stdout, stderr, status = Open3.capture3(
      "gh", "release", "view", tag, "--repo", repository, "--json", "assets,isDraft"
    )
    exists = status.success?
    unless exists
      unless /release not found|HTTP 404/i.match?(stderr)
        raise "Cannot inspect the release: #{stderr.strip}"
      end
      raise "No existing release found for #{tag}" if event_name == "workflow_dispatch"
    end

    release = exists ? JSON.parse(stdout) : { "assets" => [], "isDraft" => true }
    assets = release.fetch("assets") || []
    archive = "WakeMyMac_#{tag.delete_prefix("v")}.tar.gz"
    binary = assets.find { |asset| asset.fetch("name") == archive }
    incomplete = binary && (binary["state"] == "starter" || binary.fetch("size", 1).zero?)

    File.write(output, JSON.generate(release))
    {
      "exists" => exists,
      "has_binary" => !binary.nil? && !incomplete,
      "replace_incomplete_binary" => !!incomplete,
      "is_draft" => release.fetch("isDraft"),
      "version" => tag.delete_prefix("v")
    }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on("--tag TAG") { |value| options[:tag] = value }
    parser.on("--repository OWNER/REPOSITORY") { |value| options[:repository] = value }
    parser.on("--event EVENT") { |value| options[:event_name] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
  end.parse!

  begin
    ReleaseState.inspect_release(**options).each { |name, value| puts "#{name}=#{value}" }
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
