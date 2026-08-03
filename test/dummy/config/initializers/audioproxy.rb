# Fixture for the "explicit configuration wins" requirement: ENV sets
# AP_ALLOW_INSECURE=true, and this app initializer — which runs after every
# railtie initializer — takes it back.
Audioproxy.configure do |config|
  config.unsigned = false
end
