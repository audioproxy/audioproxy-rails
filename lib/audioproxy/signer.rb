require "base64"
require "openssl"

module Audioproxy
  # Signature building — the one piece that must stay liftable into a standalone
  # gem. It therefore depends on stdlib and base64 only: no ActiveSupport, no
  # Rails, and nothing else in this gem. Everything it needs arrives through the
  # constructor, so extracting it is a `git mv` plus a gemspec, not a rewrite.
  #
  # Byte contract, mirroring the proxy's reference signer:
  #
  #   base64url(HMAC-SHA256(key, salt ‖ rest_of_path))   — unpadded
  #
  # where key and salt are the decoded binary values and +rest_of_path+ is the
  # exact byte sequence after the signature segment, leading "/" included.
  class Signer
    DIGEST = "SHA256".freeze

    attr_reader :key, :salt

    def initialize(key:, salt:)
      @key = key
      @salt = salt
    end

    def sign(rest_of_path)
      unless rest_of_path.start_with?("/")
        raise ArgumentError, "rest_of_path must begin with '/' to be verifiable at the proxy, got #{rest_of_path.inspect}"
      end

      # .b so a non-ASCII path cannot raise Encoding::CompatibilityError against
      # the binary salt.
      digest = OpenSSL::HMAC.digest(DIGEST, key, salt + rest_of_path.b)

      # Unpadded: the proxy accepts both spellings, but emitting exactly one
      # keeps URLs and CDN cache keys stable.
      Base64.urlsafe_encode64(digest, padding: false)
    end
  end
end
