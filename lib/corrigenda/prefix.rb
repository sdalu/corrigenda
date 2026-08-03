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
