require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/keys"
require "audioproxy/rails/helpers"

module Audioproxy
  module Rails
    # Wires an app's configuration and view helpers. Not an engine: there are no
    # routes, views or migrations to mount.
    class Railtie < ::Rails::Railtie
      # Attribute -> environment variable. The names are the proxy's own, so a
      # dev docker-compose can feed the app and the proxy from one env file
      # (D2). AP_ALLOW_INSECURE maps to +unsigned+, which is only the *client's*
      # flag — the proxy enforces its own independently.
      ENV_VARIABLES = {
        endpoint: "AP_ENDPOINT",
        key: "AP_KEY",
        salt: "AP_SALT",
        unsigned: "AP_ALLOW_INSECURE"
      }.freeze

      # The literals Go's strconv.ParseBool accepts, which is what the proxy
      # parses AP_ALLOW_INSECURE with. Deliberately *not* ActiveModel's boolean
      # cast: that reads every unrecognized string as true, so a stray
      # AP_ALLOW_INSECURE=flase would quietly ship unsigned URLs.
      TRUE_VALUES = %w[1 t true].freeze
      FALSE_VALUES = %w[0 f false].freeze

      initializer "audioproxy.config" do
        Railtie.apply_configuration(
          Audioproxy.config,
          credentials: ::Rails.application.credentials.audioproxy,
          env: ENV
        )
      end

      initializer "audioproxy.helpers" do
        ActiveSupport.on_load(:action_view) { include Audioproxy::Rails::Helpers }
      end

      class << self
        # Sources each attribute independently: credentials first, ENV where
        # credentials are silent, nothing at all where both are. Absent
        # configuration is not an error here — a signed +url_for+ later raises
        # the core's ConfigurationError, while an app running unsigned in
        # development never needs a key (D3). Validating at boot would break
        # `assets:precompile` and friends in apps that never generate a URL.
        #
        # Runs in a railtie initializer, so an app's own
        # `config/initializers/*.rb` gets the last word for free.
        def apply_configuration(config, credentials:, env:)
          credentials = normalize_credentials(credentials)

          ENV_VARIABLES.each do |attribute, variable|
            value = credentials[attribute]
            source = :credentials

            if value.nil?
              # Blank is absent: an env file that carries AP_KEY= with nothing
              # after it should fall through, not hand Config an empty string.
              value = env[variable].presence
              source = variable
            end

            next if value.nil?

            value = coerce_boolean(value, attribute, source) if attribute == :unsigned
            config.public_send(:"#{attribute}=", value)
          end

          config
        end

        private
          # Credentials reach us deep-symbolized in current Rails, but a stub or
          # an older shape can hand over strings; normalizing in one place is
          # what keeps the rest of this indifferent.
          #
          # Unknown keys under `audioproxy:` are left alone rather than raising.
          # Unlike a typo in default_options, a typo here cannot produce a
          # valid-looking URL for the wrong variant — it produces no
          # configuration, and the core then raises at url_for.
          def normalize_credentials(credentials)
            return {} if credentials.nil?

            unless credentials.respond_to?(:to_h)
              raise ArgumentError,
                "Audioproxy credentials must be a Hash of endpoint/key/salt/unsigned, got #{credentials.class}"
            end

            hash = credentials.to_h

            hash.each_key do |key|
              unless key.is_a?(String) || key.is_a?(Symbol)
                raise ArgumentError, "Audioproxy credentials keys must be Strings or Symbols, got #{key.class}"
              end
            end

            duplicate = hash.keys.group_by(&:to_sym).find { |_, spellings| spellings.size > 1 }
            if duplicate
              key, spellings = duplicate
              raise ArgumentError,
                "Audioproxy credentials give #{key} twice, as " \
                "#{spellings.map(&:inspect).join(" and ")}; each setting takes one spelling"
            end

            hash.symbolize_keys
          end

          def coerce_boolean(value, attribute, source)
            return value if value == true || value == false

            case String.try_convert(value)&.downcase
            when *TRUE_VALUES then true
            when *FALSE_VALUES then false
            else
              raise ArgumentError,
                "Audioproxy #{attribute} from #{source} must be one of " \
                "#{(TRUE_VALUES + FALSE_VALUES).join(", ")} (or a YAML boolean), got #{value.inspect}"
            end
          end
      end
    end
  end
end
