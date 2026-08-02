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

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # Rails is deliberately *not* a runtime dependency: the core loads Rails-free
  # and the railtie is required only when Rails is already present.
  spec.add_development_dependency "rails", "~> 8.1", ">= 8.1.3.1"
end
