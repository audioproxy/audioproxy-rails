require "audioproxy"

module Audioproxy
  module Rails
    # Mixed into ActionView by the railtie. Thin on purpose: URL construction is
    # the core's job, and these only carry it into views.
    module Helpers
      # Every option goes through to Audioproxy.url_for untouched, so views and
      # jobs share one vocabulary.
      def audioproxy_url(source, **options)
        Audioproxy.url_for(source, **options)
      end

      # The html: bucket is the seam between proxy options and tag attributes
      # (D4). Without it, proxy option keys and HTML attribute names share one
      # namespace, and a typoed option lands silently on the <audio> element
      # instead of raising.
      def audioproxy_audio_tag(source, html: {}, **options)
        unless html.is_a?(Hash)
          raise ArgumentError, "audioproxy_audio_tag html: must be a Hash of tag attributes, got #{html.class}"
        end

        audio_tag(audioproxy_url(source, **options), **html)
      end
    end
  end
end
