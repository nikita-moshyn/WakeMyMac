# Run with `brew ruby scripts/verify-homebrew-bottle.rb TAP/wakemymac`.
# This installs into the selected Homebrew prefix; use a disposable CI runner.
require "formula"
require "formula_installer"
require "install"

formula = Formula[ARGV.fetch(0)]
abort "Uninstall the build-bottle installation before this check" if formula.any_version_installed?

%w[arm64_sonoma sonoma arm64_sequoia sequoia arm64_tahoe tahoe].each do |tag_name|
  tag = Utils::Bottles::Tag.from_symbol(tag_name.to_sym)
  bottle = formula.bottle_for_tag(tag)
  abort "No bottle available for #{tag_name}" unless bottle
  unless formula.bottle_specification.skip_relocation?(tag: tag)
    abort "The #{tag_name} bottle requires relocation"
  end
end

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
