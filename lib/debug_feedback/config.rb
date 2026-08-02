# frozen_string_literal: true

require "pathname"
require "yaml"

module DebugFeedback
    # Runtime configuration. One YAML file per deployment; every key has
    # a default, so an absent file is a valid (development) config.
    class Config
        DEFAULTS = {
            "store"          => "store",
            "max_body"       => 8  * 1024 * 1024,
            "max_report"     => 512 * 1024,
            "max_screenshot" => 2  * 1024 * 1024,
            "max_snapshot"   => 4  * 1024 * 1024,

            # Three different questions, and they were one answer until
            # a site stopped mounting the service:
            #
            #   endpoint  where this service answers, as the public URL
            #             a site should be pointed at. It cannot work
            #             this out for itself: it is behind a proxy that
            #             strips the path it is served under.
            #   sites     what a report may claim to be about.
            #   origins   which pages may post one from another host.
            #
            # origins defaults to sites, because a site's pages are
            # served from a host of the same name and repeating the list
            # is how two lists start disagreeing. Set it only when the
            # two genuinely differ.
            "endpoint"       => nil,
            "sites"          => nil,   # nil means "accept any site"
            "origins"        => nil    # nil means "the sites, as https"
        }.freeze

        def self.load(path = ENV["DEBUG_FEEDBACK_CONFIG"])
            new(from_file(path).merge(from_env))
        end

        def self.from_file(path)
            return {} if path.nil? || !File.exist?(path)

            YAML.safe_load_file(path) || {}
        end

        # So one config file serves both the installed service and a run
        # from the working copy: the two keys that cannot be shared are
        # the store (a local run must not write the real one) and the
        # allowlist (a local run has no vhost to be on).
        def self.from_env
            values = {}
            store = ENV["DEBUG_FEEDBACK_STORE"]
            sites = ENV["DEBUG_FEEDBACK_SITES"]
            values["store"] = store unless store.nil?
            values["sites"] = parse_sites(sites) unless sites.nil?
            values
        end

        # Empty means "no allowlist", which is not the same as unset.
        def self.parse_sites(value)
            list = value.split(",").map(&:strip).reject(&:empty?)
            list.empty? ? nil : list
        end

        def initialize(values = {})
            @values = DEFAULTS.merge(values)
        end

        def store_path = Pathname(@values.fetch("store"))
        def max_body       = Integer(@values.fetch("max_body"))
        def max_report     = Integer(@values.fetch("max_report"))
        def max_screenshot = Integer(@values.fetch("max_screenshot"))
        def max_snapshot   = Integer(@values.fetch("max_snapshot"))

        # nil means no allowlist: every site is accepted.
        def sites = @values.fetch("sites")

        # An unlisted site is refused, so a stray endpoint cannot be used
        # as free storage. A nil list disables the check for development.
        def site_allowed?(site)
            sites = @values.fetch("sites")
            return true if sites.nil?

            sites.include?(site)
        end

        # Which origins may post from another host. Derived from the site
        # list rather than configured beside it: a second list is a list
        # that falls out of step, and the answer to "may this page send
        # reports" was never going to differ from "may a report say it
        # came from that site".
        #
        # The public URL of this service, without a trailing slash, or
        # nil when nobody said. Only ever displayed: what a report does
        # is decided by where it arrived, not by this.
        def endpoint
            value = @values.fetch("endpoint")
            value&.sub(%r{/+\z}, "")
        end

        # Written out when they differ from the sites, derived from them
        # when they do not. Either way this is a list of origins, and an
        # origin is a scheme and a host: a bare hostname in the file is
        # read as https, since that is the only scheme a page on this
        # estate is served over.
        def origins
            listed = @values.fetch("origins")
            return normalise(listed) unless listed.nil?

            sites = @values.fetch("sites")
            sites.nil? ? nil : normalise(sites)
        end

        # https only, with one exception: loopback, where there is no
        # certificate to have and a test would otherwise have to invent
        # one. A page served over http on this estate is a page being
        # redirected, and a credentialed cross-origin POST is not
        # something to accept from a scheme that cannot keep it.
        LOOPBACK = %w[localhost 127.0.0.1 [::1]].freeze

        def origin_allowed?(origin)
            return false if origin.nil? || origin.empty?

            scheme, rest = origin.split("://", 2)
            return false if rest.nil? || rest.empty?

            host = rest.sub(/:\d+\z/, "")
            return false unless scheme == "https" ||
                                (scheme == "http" && LOOPBACK.include?(host))

            allowed = origins
            allowed.nil? ? true : allowed.include?(origin)
        end

        def max_for(part)
            case part
            when :report     then max_report
            when :screenshot then max_screenshot
            when :snapshot   then max_snapshot
            else raise ArgumentError, "unknown part: #{part}"
            end
        end

        private

        # A bare hostname is an origin over https; anything already
        # carrying a scheme is left as it is, which is how a port or a
        # loopback entry gets in.
        def normalise(values)
            values.map { it.include?("://") ? it : "https://#{it}" }
        end
    end
end
