# frozen_string_literal: true

require "pathname"
require "yaml"

module Corrigenda
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
            "origins"        => nil,   # nil means "the sites, as https"

            # How long a report stays, in days, per rule. nil -- the
            # default, and what every deployment did before there was a
            # key -- means nothing ever expires: reports are somebody's
            # bug list, and a tool that quietly deletes one is worse than
            # a disk that fills up slowly and visibly.
            "retention"      => nil,

            # The JSON interface for a program rather than a person. nil
            # means it is not there at all, which is the default: a
            # deployment that wants no agent near its reports should not
            # have to switch one off.
            "api"            => nil
        }.freeze

        # What a caller may be allowed to do, in the order they are
        # worth thinking about: a journal line is additive, archiving
        # hides work and is reversible, a state is a claim somebody
        # stops checking behind. Deleting is not here and never will be.
        API_GRANTS = %w[journal archive state].freeze

        API_KEYS = %w[token write].freeze

        # `api: true` in full: the interface, and nothing it can change.
        READ_ONLY = { "token" => nil, "allows" => [] }.freeze

        # `archived` is the rule anyone should reach for first: it counts
        # from the moment a person said they were done looking, so it
        # expires what was dealt with rather than what is merely old.
        # `any` is the backstop for reports nobody ever triaged.
        RETENTION_RULES = %w[archived any].freeze

        def self.load(path = ENV["CORRIGENDA_CONFIG"])
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
            store = ENV["CORRIGENDA_STORE"]
            sites = ENV["CORRIGENDA_SITES"]
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

        # Where the service listens, when it listens on a socket --
        # which is how a program on this host reaches it without meeting
        # Apache. The app never binds it (../run does); it is here so a
        # page can tell somebody the path rather than have them look it
        # up.
        def socket = @values["socket"]

        # nil means no allowlist: every site is accepted.
        def sites = @values.fetch("sites")

        # An unlisted site is refused, so a stray endpoint cannot be used
        # as free storage. A nil list disables the check for development.
        def site_allowed?(site)
            sites = @values.fetch("sites")
            return true if sites.nil?

            sites.include?(site)
        end

        # The public URL of this service, without a trailing slash, or
        # nil when nobody said. Only ever displayed: what a report does
        # is decided by where it arrived, not by this.
        def endpoint
            value = @values.fetch("endpoint")
            value&.sub(%r{/+\z}, "")
        end

        # Which origins may post from another host. Written out when
        # they differ from the sites, derived from them when they do
        # not: a second list is a list that falls out of step, and the
        # answer to "may this page send reports" was never going to
        # differ from "may a report say it came from that site".
        #
        # Either way this is a list of origins, and an origin is a
        # scheme and a host: a bare hostname in the file is read as
        # https, since that is the only scheme a page on this estate is
        # served over.
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

        # nil when nothing expires, otherwise the rules that say what
        # does, as whole days. Read strictly and refused loudly: this is
        # the one setting whose mistakes are unrecoverable, and a typo
        # that silently means "no retention" would be found the day
        # somebody wondered why the disk never emptied -- while a typo
        # read as a smaller number than intended cannot happen at all,
        # because nothing here guesses.
        def retention
            values = @values.fetch("retention")
            return nil if values.nil?

            unless values.is_a?(Hash)
                raise ArgumentError,
                      "retention: expected " \
                      "#{RETENTION_RULES.join(" and/or ")}, " \
                      "got #{values.class}"
            end

            rules = values.compact.to_h { |rule, days| [rule.to_s, days] }

            unknown = rules.keys - RETENTION_RULES
            unless unknown.empty?
                raise ArgumentError,
                      "retention: no such rule #{unknown.join(", ")} " \
                      "(#{RETENTION_RULES.join(", ")})"
            end

            rules = rules.to_h { |rule, days| [rule, whole_days(rule, days)] }
            rules.empty? ? nil : rules.freeze
        end

        # nil when there is no agent interface, otherwise what it is
        # allowed to do. `api: true` is the whole of a read-only one;
        # a mapping adds a token, or write access, or both.
        #
        # Read strictly, like retention and for the same reason: this
        # one decides whether something that acts on its own reading of
        # a page may change what a person filed, and a typo must not be
        # the thing that decides it.
        def api
            value = @values.fetch("api")
            return nil if value.nil? || value == false
            return READ_ONLY if value == true

            unless value.is_a?(Hash)
                raise ArgumentError,
                      "api: expected true, or #{API_KEYS.join(" and ")}, " \
                      "got #{value.class}"
            end

            unknown = value.keys.map(&:to_s) - API_KEYS
            unless unknown.empty?
                # The grants were their own keys for an afternoon, and
                # `record` before them. A config still written that way
                # is not a typo, it is one version behind — so say what
                # it should be rather than only that it is wrong.
                was = unknown & (API_GRANTS + ["record"])
                instead = was.map { it == "record" ? "journal" : it }

                raise ArgumentError,
                      "api: no such setting #{unknown.join(", ")} " \
                      "(#{API_KEYS.join(", ")})" +
                      (was.empty? ? "" : " -- write: [#{instead.join(", ")}]")
            end

            { "token" => api_token(value["token"]),
              "allows" => api_grants(value["write"]) }.freeze
        end

        # The interface's state in a few words, for a startup line and a
        # page that both have to say it. One sentence, one definition:
        # the rule that `record` follows `write` lives above, and
        # nothing that displays this should be reimplementing it.
        GRANT_WORDS = { "journal" => "record work",
                        "archive" => "archive",
                        "state"   => "set states" }.freeze

        def api_state
            settings = api
            return "off" if settings.nil?

            said = []
            granted = settings["allows"].map { GRANT_WORDS.fetch(it) }
            said << (granted.empty? ? "read-only" : "may #{granted.join(", ")}")
            said << "token required" unless settings["token"].nil?
            said.join(", ")
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

        # Three powers, named for what they do rather than bundled into
        # one word, because they are wrong in different ways: a journal
        # line is additive and costs noise; archiving hides work and is
        # reversible; a state is a claim somebody will trust and stop
        # checking behind. Deleting is not among them at any setting.
        #
        # `write` and `record` stay as the shorthands they were, so a
        # config written before the grants existed still says what it
        # meant: everything, and the journal.
        # `write:` is a list of what a caller may do -- and reads as
        # one: "write: [journal, state]" is a sentence. `true` is all of
        # them, for a deployment that means it; anything else is refused
        # by name rather than guessed at, since every wrong reading of
        # this key either opens something or quietly closes it.
        def api_grants(value)
            return []          if value.nil? || value == false
            return API_GRANTS  if value == true

            wanted = Array(value).map(&:to_s)
            unknown = wanted - API_GRANTS
            unless unknown.empty?
                raise ArgumentError,
                      "api: write: no such grant #{unknown.join(", ")} " \
                      "(#{API_GRANTS.join(", ")})"
            end

            API_GRANTS & wanted   # a stable order, for display
        end

        # A token is a secret or it is nothing. An empty string in the
        # file means somebody meant to paste one and did not, and reading
        # that as "no token wanted" would open the interface at the exact
        # moment they were trying to close it.
        def api_token(value)
            return nil if value.nil?

            token = value.to_s
            return token unless token.strip.empty?

            raise ArgumentError, "api: token is empty -- remove the key, " \
                                 "or give it a secret"
        end

        # Days, whole and positive. Zero is refused rather than read as
        # "delete on sight": a config saying 0 is far more likely to be
        # an unfinished edit than a deployment that wants its reports
        # gone the moment they arrive.
        def whole_days(rule, days)
            value = Integer(days, exception: false)
            return value if value&.positive?

            raise ArgumentError,
                  "retention: #{rule} wants a number of days, " \
                  "got #{days.inspect}"
        end

        # A bare hostname is an origin over https; anything already
        # carrying a scheme is left as it is, which is how a port or a
        # loopback entry gets in.
        def normalise(values)
            values.map { it.include?("://") ? it : "https://#{it}" }
        end
    end
end
