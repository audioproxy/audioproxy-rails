# Known-answer test vectors for the audioproxy URL signature.
#
# Copied verbatim from the audioproxy server's published vectors for
# `AudioProxy.Signature`. They pin the cross-implementation byte contract: if
# this gem stops reproducing them, the URLs it emits will 403 at the proxy.
# If the proxy ever rotates its vectors, re-copy them from the server repo's
# signature test vectors rather than regenerating them from this gem.
#
# The vectors were generated with:
#
#   import hashlib, hmac, base64
#   key  = bytes.fromhex("00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF")
#   salt = bytes.fromhex("FFEEDDCCBBAA99887766554433221100")
#   for path in ("/f:opus/br:96/plain/s3://masters/2026/piece-final.wav",
#                "/info/plain/s3://b/k.wav"):
#       digest = hmac.new(key, salt + path.encode(), hashlib.sha256).digest()
#       print(path, base64.urlsafe_b64encode(digest).rstrip(b"=").decode())
#
# Note the `plain/` sources: signing is agnostic to what the path bytes mean,
# so the vectors exercise the signer independently of the `enc/` form this gem
# emits.
module SignatureVectors
  KEY_HEX  = "00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF".freeze
  SALT_HEX = "FFEEDDCCBBAA99887766554433221100".freeze

  VECTORS = [
    {
      rest_of_path: "/f:opus/br:96/plain/s3://masters/2026/piece-final.wav",
      signature: "zfLTfPPhQ8kdeYYJOdagqPfog2nFk7KzDFUjtRAf_Ns"
    },
    {
      rest_of_path: "/info/plain/s3://b/k.wav",
      signature: "U6nyFdkSvjNo2mlBbJMGk1nwISbdcnEGlgKSWKBfKT4"
    }
  ].freeze
end
