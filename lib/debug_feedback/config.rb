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
            "sites"          => nil    # nil means "accept any site"
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

            sites = @values.fetch("sites")
            sites.nil? ? true : sites.include?(host)
        end

        def max_for(part)
            case part
            when :report     then max_report
            when :screenshot then max_screenshot
            when :snapshot   then max_snapshot
            else raise ArgumentError, "unknown part: #{part}"
            end
        end
    end
end
