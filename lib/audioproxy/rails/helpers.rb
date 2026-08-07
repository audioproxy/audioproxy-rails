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

      # `as` is supplied rather than inferred: ActionView reads it off the
      # source's file extension, and a proxy URL ends in an encoded source
      # segment that has none, so the inference always fails here. A preload
      # with no `as` has no fetch destination and browsers decline to act on it.
      #
      # No crossorigin, matching what audioproxy_audio_tag emits. A preload
      # whose crossorigin disagrees with the element consuming it downloads the
      # whole variant twice; a caller who sets one on the tag sets the same one
      # here.
      def audioproxy_preload_link_tag(source, html: {}, **options)
        unless html.is_a?(Hash)
          raise ArgumentError, "audioproxy_preload_link_tag html: must be a Hash of tag attributes, got #{html.class}"
        end

        attributes = { as: "audio" }.merge(html.symbolize_keys)

        # A blank `as` is not an override, it is the destination-less tag this
        # helper exists to prevent: ActionView falls through to its extension
        # inference, which has nothing to work with, and the attribute is
        # dropped entirely.
        if attributes[:as].blank?
          raise ArgumentError,
            "audioproxy_preload_link_tag as: must name a fetch destination, got #{attributes[:as].inspect} " \
            "(a rel=preload without one is ignored by browsers; pass as: \"audio\" or omit it)"
        end

        # ActionView renders crossorigin: true as "anonymous" here and audio_tag
        # renders it as "true", so the pair disagrees and the browser fetches the
        # variant twice — the one failure this helper's crossorigin default (D3)
        # exists to avoid.
        if attributes[:crossorigin] == true
          raise ArgumentError,
            "audioproxy_preload_link_tag crossorigin: must be a String, got true " \
            "(it would render as \"anonymous\" here and \"true\" on the audio tag, fetching the variant twice)"
        end

        preload_link_tag(audioproxy_url(source, **options), attributes)
      end
    end
  end
end
