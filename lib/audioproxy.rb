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
  end
end

require "audioproxy/rails/railtie" if defined?(::Rails::Railtie)
