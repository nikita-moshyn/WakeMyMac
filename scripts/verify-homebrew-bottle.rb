# Run with `brew ruby scripts/verify-homebrew-bottle.rb TAP/wakemymac ASSET_DIRECTORY`.
# This installs into the selected Homebrew prefix; use a disposable CI runner.
require "digest"
require "formula"
require "formula_installer"
require "install"
require "uri"

def verified_asset(bottle, asset_directory)
  filename = URI::DEFAULT_PARSER.unescape(File.basename(URI.parse(bottle.url).path))
  asset = asset_directory/filename
  abort "Published bottle is missing for Homebrew URL: #{bottle.url}" unless asset.file?
  unless Digest::SHA256.file(asset).hexdigest == bottle.resource.checksum.hexdigest
    abort "Published bottle checksum does not match Homebrew URL: #{bottle.url}"
  end
  asset
end

formula = Formula[ARGV.fetch(0)]
asset_directory = Pathname(ARGV.fetch(1)).expand_path
abort "Uninstall the build-bottle installation before this check" if formula.any_version_installed?

%w[arm64_sonoma sonoma arm64_sequoia sequoia arm64_tahoe tahoe].each do |tag_name|
  tag = Utils::Bottles::Tag.from_symbol(tag_name.to_sym)
  bottle = formula.bottle_for_tag(tag)
  abort "No bottle available for #{tag_name}" unless bottle
  unless formula.bottle_specification.skip_relocation?(tag: tag)
    abort "The #{tag_name} bottle requires relocation"
  end
  verified_asset(bottle, asset_directory)
end

# Match assets to Homebrew's actual download URLs before seeding its cache.
# A cache copy alone would not catch a wrongly named GitHub Release asset.
bottle = formula.bottle
abort "No bottle available for this system" unless bottle
asset = verified_asset(bottle, asset_directory)
bottle.cached_download.dirname.mkpath
FileUtils.cp(asset, bottle.cached_download)

# Exercise the actual installer with the conditions that caused the reported
# error. Never bypass these checks in production formulae or in Homebrew itself.
MacOS::Xcode.define_singleton_method(:installed?) { false }
MacOS::CLT.define_singleton_method(:installed?) { false }
DevelopmentTools.define_singleton_method(:installed?) { false }

Homebrew::Install.define_singleton_method(:perform_build_from_source_checks) do |*|
  raise "A binary installation must not run source-build checks"
end

installer = FormulaInstaller.new(formula)
abort "Homebrew would fall back to a source build" unless installer.pour_bottle?
installer.prelude
installer.fetch
installer.install
installer.finish

abort "Homebrew did not record a bottle installation" unless Tab.for_formula(formula).poured_from_bottle
abort "The installed binary did not run" unless system(formula.bin/"wake", "--version")

puts "Bottle installation passed with Xcode and Command Line Tools detection disabled."
