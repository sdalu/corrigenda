# frozen_string_literal: true

module Corrigenda
    # Apache strips the <Location> prefix before proxying, so the app is
    # served at /.corrigenda/review but is told only /review. Every
    # link it generated therefore pointed at a path that does not exist
    # on the vhost.
    #
    # The prefix comes back as a header and is put where Rack expects it,
    # so Sinatra's `to` builds correct paths and no template has to know
    # it is behind a proxy.
    # The masthead is shared, but Home is mounted at / and Review at
    # /review, so `to` builds different things in each. The mount root is
    # what the proxy told us, and it is the same for both.
    module MountPath
        # The proxy's header first: only Apache knows the path this
        # is served under, since it strips the Location before
        # proxying. Failing that, SCRIPT_NAME, which Rack::URLMap
        # sets when the app is mounted locally -- without it a
        # bookmarklet built by a local run points at the wrong
        # place and every link in the masthead loses its prefix.
        def mount(path)
            prefix = request.env[Prefix::HEADER]
            prefix = request.env["SCRIPT_NAME"] if prefix.to_s.empty?
            "#{prefix.to_s.chomp('/')}#{path}"
        end

        # Whether this deployment has a JSON interface at all, which is
        # what decides if the masthead offers a tab for its schema. A
        # tab leading to a 404 is worse than no tab.
        #
        # A config that cannot be read is answered "no" rather than
        # allowed to take a page down: the interface being described is
        # not what somebody came to this page for.
        def api_offered?
            !settings.feedback_config.api.nil?
        rescue ArgumentError
            false
        end

# The three questions a page asks about it, rather than making a
# template dig into the settings hash and repeat the rule that
# `record` follows `write`.
def api_allows_writes?  = api_settings["write"] == true
def api_allows_records? = api_settings["record"] == true
def api_needs_token?    = !api_settings["token"].nil?

def api_settings
    settings.feedback_config.api || {}
rescue ArgumentError
    {}
end

        # What it will let a caller do, in the words the startup
        # line uses. Both come from Config, so a page and a terminal
        # cannot describe the same deployment differently.
        def api_state
            settings.feedback_config.api_state
        rescue ArgumentError => e
            "misconfigured — #{e.message}"
        end
    end

    class Prefix
        HEADER = "HTTP_X_FORWARDED_PREFIX"

        def initialize(app)
            @app = app
        end

        def call(env)
            prefix = env[HEADER].to_s.chomp("/")
            env["SCRIPT_NAME"] = prefix + env["SCRIPT_NAME"].to_s unless prefix.empty?
            @app.call(env)
        end
    end
end
