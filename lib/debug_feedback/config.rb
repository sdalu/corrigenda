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

        # DEBUG_FEEDBACK_STORE wins over the file, so a caller can point
        # one config at a different store without writing a second one.
        def self.load(path = ENV["DEBUG_FEEDBACK_CONFIG"])
            values = if path.nil? || !File.exist?(path)
                         {}
                     else
                         YAML.safe_load_file(path) || {}
                     end
            store = ENV["DEBUG_FEEDBACK_STORE"]
            values = values.merge("store" => store) unless store.nil?
            new(values)
        end

        def initialize(values = {})
            @values = DEFAULTS.merge(values)
        end

        def store_path = Pathname(@values.fetch("store"))
        def max_body       = Integer(@values.fetch("max_body"))
        def max_report     = Integer(@values.fetch("max_report"))
        def max_screenshot = Integer(@values.fetch("max_screenshot"))
        def max_snapshot   = Integer(@values.fetch("max_snapshot"))

        # An unlisted site is refused, so a stray endpoint cannot be used
        # as free storage. A nil list disables the check for development.
        def site_allowed?(site)
            sites = @values.fetch("sites")
            return true if sites.nil?

            sites.include?(site)
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
