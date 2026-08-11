require_relative "lib/audioproxy/version"

Gem::Specification.new do |spec|
  spec.name        = "audioproxy-rails"
  spec.version     = Audioproxy::VERSION
  spec.authors     = [ "Julian Rubisch" ]
  spec.email       = [ "julian@julianrubisch.at" ]
  spec.homepage    = "https://github.com/audioproxy/audioproxy-rails"
  spec.summary     = "Signed variant URLs for the audioproxy server."
  spec.description = "Builds signed, option-carrying URLs for the audioproxy media server, with a Rails integration layer on top of a Rails-free core."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  # No source_code_uri: it would be the homepage, and RubyGems shows only one of the two.
  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # A leaked API key alone should not be enough to push a version.
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only lib/. This gem is deliberately not an engine, so app/, config/, and db/
  # have nothing to contribute; globbing them would silently package the engine
  # artifacts the gem-packaging spec rules out.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "MIT-LICENSE", "README.md", "CHANGELOG.md"]
  end

  # Declared because Audioproxy::Signer requires it directly. Since Ruby 3.4
  # base64 is a bundled gem rather than a default one, so leaning on
  # ActiveSupport to pull it in transitively would be a latent LoadError the
  # moment that changed.
  spec.add_dependency "base64"

  # This is a Rails integration, so ActiveSupport is a reasonable runtime
  # dependency. Audioproxy::Signer deliberately does not use it (D1), which is
  # what keeps signature building liftable into a standalone gem.
  spec.add_dependency "activesupport", ">= 7.1"

  # Full Rails is *not* a runtime dependency: the railtie is required only when
  # Rails is already present.
  spec.add_development_dependency "rails", "~> 8.1", ">= 8.1.3.1"
end
