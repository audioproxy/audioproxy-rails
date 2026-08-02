require "audioproxy/version"

# Rails-free core. Nothing in this namespace may reference Rails constants.
module Audioproxy
end

require "audioproxy/rails/railtie" if defined?(::Rails::Railtie)
