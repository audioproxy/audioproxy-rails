require "audioproxy/version"
require "audioproxy/signer"
require "audioproxy/options"
require "audioproxy/config"
require "audioproxy/url_builder"

# Nothing in this namespace may reference Rails constants; ActiveSupport is
# fair game except inside Audioproxy::Signer, which stays liftable. See D1.
module Audioproxy
  class << self
    attr_writer :config

    def config
      @config ||= Config.new
    end

    def configure
      yield config
      config
    end

    # Single public entry point: usable from jobs, mailers and serializers of
    # any Ruby program, Rails or not.
    def url_for(source, **options)
      UrlBuilder.new(config).url_for(source, **options)
    end

    # Anything that is not already a source String is handed to this resolver.
    # The Rails layer registers one for ActiveStorage objects; the core stays
    # ignorant of what a blob is, which is what keeps +url_for+ usable with no
    # Rails loaded at all (D5).
    attr_reader :source_resolver

    def register_source_resolver(resolver = nil, &block)
      resolver ||= block

      unless resolver.respond_to?(:call)
        raise ArgumentError, "an Audioproxy source resolver must respond to #call, got #{resolver.class}"
      end

      @source_resolver = resolver
    end

    def reset_source_resolver
      @source_resolver = nil
    end
  end
end

require "audioproxy/rails/railtie" if defined?(::Rails::Railtie)
