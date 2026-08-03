# frozen_string_literal: true

require "json"
require "openssl"      # secure_compare, for the token
require "sinatra/base"

require_relative "../corrigenda"
require_relative "prefix"

module Corrigenda
    # The same reports, for a reader that is a program. The review UI is
    # HTML meant for a person: an agent asked to fix what was reported
    # would have to scrape it, and would then be reading a layout rather
    # than a report.
    #
    # Off unless the deployment asks for it. An estate that does not put
    # agents anywhere near its bug list should not have to argue with an
    # interface built for them, so an absent `ai:` key means every path
    # here answers 404 — not 403, because a route that is switched off
    # should not advertise that it exists.
    class AI < Sinatra::Base
        ID = /\A\d{8}T\d{6}Z-[0-9a-f]{8}\z/

        SERVABLE = {
            "screenshot.webp" => "image/webp",
            "snapshot.html"   => "text/html",
            "report.json"     => "application/json"
        }.freeze

        configure do
            set :feedback_config, Config.load
            set :show_exceptions, false
            set :host_authorization, { permitted_hosts: [] }
        end

        helpers do
            def config = settings.feedback_config

            def store = @store ||= Store.new(config.store_path)

            def ai = config.ai

            # JSON out, always, including for the refusals: a client that
            # has to tell an error page from a report by looking at it is
            # a client that will get it wrong once.
            def json(object, status: 200)
                content_type "application/json"
                halt status, JSON.pretty_generate(object) + "\n"
            end

            def fail_with(status, message) = json({ "error" => message },
                                                  status:)

            def report!(id)
                fail_with(404, "no such report: #{id}") unless id.match?(ID)

                document = store.read(id)
                fail_with(404, "no such report: #{id}") if document.nil?

                document
            end

            # A report as this interface hands it over: the document as
            # filed, plus the two things that are not in it -- what has
            # happened to it since, and what arrived beside it.
            def described(id, document)
                {
                    "id"       => id,
                    "state"    => store.state(id),
                    "archived" => store.archived?(id),
                    "files"    => store.files(id).reject { it == "state" },
                    "report"   => document
                }
            end

            # A form post is what a shell reaches for first; JSON is what
            # a program sends. Both, rather than a lecture.
            #
            # The form case is answered before the body is touched, and
            # has to be: Sinatra has already read it to build `params`,
            # so reading again returns an empty string and the request
            # looks like it said nothing at all.
            def body_params
                return params.to_h if request.form_data?

                raw = request.body.read
                return {} if raw.empty?

                JSON.parse(raw)
            rescue JSON::ParserError => e
                fail_with(400, "body is not JSON: #{e.message}")
            end
        end

        # Switched off, absent, or holding the wrong token: all the same
        # answer. The token is compared in constant time -- it is short
        # and the comparison is cheap, and a timing oracle on a secret is
        # not worth the one line it saves.
        before do
            halt 404, "" if ai.nil?

            want = ai["token"]
            next if want.nil?

            given = request.env["HTTP_AUTHORIZATION"].to_s
                           .sub(/\ABearer\s+/i, "")
            given = request.env["HTTP_X_CORRIGENDA_TOKEN"].to_s if given.empty?

            unless given.bytesize == want.bytesize &&
                   OpenSSL.secure_compare(given, want)
                fail_with(401, "a token is required")
            end
        end

        # A path this app does not answer is still a JSON answer, for the
        # same reason the refusals are: the client is a program, and
        # Sinatra's own page is HTML. Left alone when the endpoint is
        # switched off (nothing is owed to a caller of a route that does
        # not exist) and when a route has already said something.
        not_found do
            next "" if ai.nil?
            next if response.body.join.length.positive?

            content_type "application/json"
            JSON.pretty_generate({ "error" => "no such route: " \
                                              "#{request.path_info}" }) + "\n"
        end

        # What is here, in the words a program needs: the routes, whether
        # it may write, and the shape of an id. An agent that lands on
        # this endpoint knowing nothing else can start from here.
        get "/" do
            json({
                "service"  => "corrigenda",
                "version"  => VERSION,
                "reports"  => store.ids.size,
                "writable" => ai["write"],
                "id"       => "YYYYMMDDThhmmssZ-xxxxxxxx",
                "states"   => Store::STATES,
                "channels" => CHANNELS.transform_values { |(_, label)| label },
                "routes"   => routes_description
            })
        end

        # The listing, filtered the way somebody actually asks: the open
        # ones, the ones about a site, the ones carrying a screenshot.
        get "/reports" do
            archived = case params[:archived]
                       when "1", "true"  then true
                       when "all"        then nil
                       else                   false
                       end

            asked = params.fetch(:limit, 100)
            limit = Integer(asked, exception: false) || 100

            # Unlimited from the store, then narrowed, then cut: a limit
            # applied first would answer "the fixed ones" with whichever
            # of the newest hundred happened to be fixed, and a client
            # cannot tell that from "there are none".
            entries = store.entries(limit: nil, archived:)
            entries = entries.select { it["state"] == params[:state] } if
                params[:state]
            entries = entries.select { it["site"] == params[:site] } if
                params[:site]

            # Both numbers, because one of them is a decision: `matched`
            # is how many answer the filter, `count` how many are in
            # this response. A client that sees them differ knows to ask
            # for more rather than concluding it has seen everything.
            shown = entries.first(limit)
            json({ "count" => shown.size, "matched" => entries.size,
                   "reports" => shown })
        end

        get "/reports/:id" do
            id = params[:id]
            json(described(id, report!(id)))
        end

        # Whitelisted, because the name is a path component -- and the
        # screenshot is the reason this route exists: an agent looking at
        # a visual defect wants the picture, not a description of it.
        get "/reports/:id/file/:name" do
            id, name = params.values_at(:id, :name)
            fail_with(404, "no such report: #{id}") unless id.match?(ID)

            type = SERVABLE[name]
            fail_with(404, "not servable: #{name}") if type.nil?

            path = store.dir_for(id) / name
            fail_with(404, "no such file: #{name}") unless path.exist?

            content_type type
            path.binread
        end

        post "/reports/:id/state" do
            writable!
            id = params[:id]
            report!(id)

            state = body_params["state"]
            unless Store::STATES.include?(state)
                fail_with(422, "no such state: #{state.inspect} " \
                               "(#{Store::STATES.join(", ")})")
            end

            store.mark(id, state)
            json(described(id, store.read(id)))
        end

        post "/reports/:id/archive" do
            writable!
            id = params[:id]
            report!(id)

            wanted = body_params.fetch("archived", true)
            store.archive(id, yes: ![false, "false", "0", 0].include?(wanted))
            json(described(id, store.read(id)))
        end

        # Deliberately absent: delete. It is the one operation with
        # nothing behind it, and an interface built for something that
        # acts on its own reading of a situation is the last place to put
        # it. The review UI asks twice; that is where it stays.

        helpers do
            def writable!
                return if ai["write"]

                fail_with(403, "this endpoint is read-only " \
                               "(set ai.write in the deployment config)")
            end

            def routes_description
                {
                    "GET /reports"             => "id, at, site, state, " \
                                                  "archived, channels, summary",
                    "GET /reports/:id"         => "the report as filed",
                    "GET /reports/:id/file/:name" =>
                        SERVABLE.keys.join(", "),
                    "POST /reports/:id/state"   => "{\"state\": \"fixed\"}",
                    "POST /reports/:id/archive" => "{\"archived\": true}"
                }
            end
        end
    end
end
