# frozen_string_literal: true

require "base64"       # a picture arrives with the note it belongs to
require "json"
require "openssl"      # secure_compare, for the token
require "sinatra/base"
require "yaml"         # the OpenAPI document, served as JSON

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
    # interface built for them, so an absent `api:` key means every path
    # here answers 404 — not 403, because a route that is switched off
    # should not advertise that it exists.
    class API < Sinatra::Base
        # The schema, beside the code it describes. Read once and held:
        # it is a few kilobytes and it cannot change while the service
        # runs, since a checkout is not edited underneath a process.
        SPEC = File.expand_path("../../openapi.yaml", __dir__)

        def self.openapi
            @openapi ||= YAML.safe_load_file(SPEC)
        end

        configure do
            set :feedback_config, Config.load
            set :show_exceptions, false
            set :host_authorization, { permitted_hosts: [] }
        end

        helpers RemoteUser

        helpers do
            def config = settings.feedback_config

            def store = @store ||= Store.new(config.store_path)

            def api = config.api

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
                fail_with(404, "no such report: #{id}") unless
                    id.match?(Store::ID)

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
                    "files"    => store.attachments(id),
                    "journal"  => store.journal(id),
                    "report"   => document
                }
            end

            # A picture for the line being written, if one came with it.
            # Base64 in the same JSON body rather than multipart: a
            # client that can send a note can send this without learning
            # a second encoding, and these are one screenshot each, not
            # a stream. A data: URL is accepted whole, because that is
            # what a browser and most agents already have in hand.
            def shot_from(fields)
                given = fields["image"]
                return nil if given.nil? || given == ""

                data = given.is_a?(Hash) ? given["data"] : given
                type = given.is_a?(Hash) ? given["type"] : nil
                data_url = %r{\Adata:(image/[\w.+-]+);base64,(.*)\z}m
                if (url = data.to_s.match(data_url))
                    type, data = url[1], url[2]
                end

                shot = { type: type || "image/webp", bytes: decoded(data) }
                return shot unless given.is_a?(Hash)

                # What the caller says the picture was taken at, carried
                # through rather than checked here: the store is what
                # files a claim beside the file name, so it is also what
                # decides whether one is a label or an essay.
                shot.merge(viewport: given["viewport"],
                           scheme: given["scheme"])
            end

            # The store is where a picture is judged -- the kinds it
            # keeps, the ceiling, the length of what the picture claims
            # about itself -- and it says no by raising. Uncaught that
            # is a 500, which tells a client the service broke when what
            # happened is that its request was refused for a reason it
            # can act on. So the refusal comes back as one, in the
            # store's own words.
            def record!(id, note, **carried)
                store.record(id, note, **carried)
            rescue StorageError => e
                fail_with(422, e.message)
            end

            def decoded(data)
                fail_with(422, "image: expected base64 data") if
                    data.to_s.empty?

                Base64.strict_decode64(data.to_s.gsub(/\s+/, ""))
            rescue ArgumentError
                fail_with(422, "image: not base64")
            end

            # A form post is what a shell reaches for first; JSON is what
            # a program sends. Both, rather than a lecture.
            #
            # The form case is answered before the body is touched, and
            # has to be: Sinatra has already read it to build `params`,
            # so reading again returns an empty string and the request
            # looks like it said nothing at all.
            # Held after the first call, and it has to be: the body is a
            # stream, so a second read returns nothing and the second
            # field a route asks for would silently be missing.
            def body_params
                @body_params ||= read_body
            end

            def read_body
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
            halt 404, "" if api.nil?

            want = api["token"]
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
            next "" if api.nil?
            next if response.body.join.length.positive?

            content_type "application/json"
            JSON.pretty_generate({ "error" => "no such route: " \
                                              "#{request.path_info}" }) + "\n"
        end

        # What is here, in the words a program needs: the routes, whether
        # it may write, and the shape of an id. A client that lands on
        # this endpoint knowing nothing else can start from here, and
        # `openapi` is where one that would rather read a schema goes.
        get "/" do
            json({
                "service"    => "corrigenda",
                "version"    => VERSION,
                "openapi"    => mounted("/openapi.json"),
                "reports"    => store.ids.size,

                # What it may do, and where it may do it: three grants
                # rather than one word, since they are wrong in
                # different ways, and the site patterns they are bounded
                # by. Reading is not a grant -- being here is reading.
                "allows"     => api["allows"],

                "id"         => "YYYYMMDDThhmmssZ-xxxxxxxx",
                "states"     => Store::STATES,
                "channels"   => CHANNELS.transform_values { |(_, l)| l },
                "routes"     => routes_description
            })
        end

        # The same interface, as a schema. Served from the file rather
        # than generated from the routes: a generated description says
        # what the code does, which is exactly the thing a reader wants
        # checked against something else. test/openapi_test.rb is what
        # keeps the two in step, and it fails on either drifting.
        #
        # One correction on the way out: the file says `/api` because a
        # file cannot know where a deployment mounts the service, and
        # the viewer's Try it out sends its requests wherever `servers`
        # points -- against the file's value, at the vhost root, where
        # nothing answers. The served copy carries the mount this
        # request actually came through.
        get "/openapi.json" do
            here = mounted("")
            spec = self.class.openapi.merge(
                "servers" => [{
                    "url"         => here.empty? ? "/api" : here,
                    "description" => "This deployment, at the mount " \
                                     "this copy was served from"
                }]
            )

            content_type "application/json"
            JSON.pretty_generate(spec) + "\n"
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

        # Where work can be, and where there is any. The allowlist is
        # what a report may claim to be about; the counts are what has
        # actually been filed, so a client can pick a site to start on
        # instead of being handed a placeholder to fill in.
        get "/sites" do
            filed = Hash.new { |all, site| all[site] = { "open" => 0,
                                                         "archived" => 0,
                                                         "total" => 0 } }

            store.entries(limit: nil, archived: nil).each do |entry|
                counts = filed[entry["site"].to_s]
                counts["total"]    += 1
                counts["archived"] += 1 if entry["archived"]
                counts["open"]     += 1 if !entry["archived"] &&
                                           entry["state"] == "open"
            end

            # Both, and in one list: a site with an open report that is
            # not on the allowlist is worth seeing (it was listed once,
            # or the list changed under it), and a site with no reports
            # yet is where somebody may still work.
            allowed = config.sites
            names   = ((allowed || []) + filed.keys).uniq.sort

            json({ "allowlist" => allowed,
                   "count"     => names.size,
                   "sites"     => names.map { |name|
                       { "site" => name, "allowed" => allowed.nil? ||
                                                      allowed.include?(name) }
                           .merge(filed[name])
                   } })
        end

        get "/reports/:id" do
            id = params[:id]
            document = report!(id)

            # Cheap and honest: the report is immutable once filed, so
            # what can change is its state, its archive marker and the
            # length of its journal — which is the whole of what a client
            # would notice. A poller that sends If-None-Match gets a 304
            # and no body.
            etag report_etag(id)
            json(described(id, document))
        end

        # One resource, one representation, a partial update: the two
        # things about a report that can change are its state and whether
        # anyone still wants to see it, and a client that wants to change
        # both should not have to make two requests and hope.
        patch "/reports/:id" do
            id = params[:id]
            changes = body_params

            # What a report can be told: where it stands, and what was
            # done about it. `agent` and `refs` describe the caller and
            # its work rather than the report, and ride along with the
            # note they belong to.
            unknown = changes.keys - %w[state archived note agent refs image]
            unless unknown.empty?
                fail_with(422, "not something a report can be told: " \
                               "#{unknown.join(", ")}")
            end

            # A picture only rides with a note -- silently dropping it
            # was the alternative, and a 200 that lost the image is the
            # kind of answer nobody debugs until they need the picture.
            if changes["image"] && !changes["note"]
                fail_with(422, "an image rides with a note: say what it shows")
            end

            # Asked for by what the body carries, not by the verb: a
            # PATCH that only says what was tried needs the permission
            # to say things, and a deployment can grant that without
            # granting the one that moves a report to fixed.
            report!(id)
            allowed!("state")   if changes.key?("state")
            allowed!("archive") if changes.key?("archived")
            allowed!("journal") if changes["note"]

            if changes.key?("state")
                state = changes["state"]
                unless Store::STATES.include?(state)
                    fail_with(422, "no such state: #{state.inspect} " \
                                   "(#{Store::STATES.join(", ")})")
                end
                store.mark(id, state, by: remote_user, agent: changes["agent"])
            end

            if changes.key?("archived")
                store.archive(id, yes: truthy(changes["archived"]),
                                  by: remote_user, agent: changes["agent"])
            end

            # A change and the reason for it, in one request: an agent
            # that has just fixed something has the sentence to hand,
            # and asking for a second call is how a trail ends up with
            # states nobody explained.
            if changes["note"]
                record!(id, changes["note"], by: remote_user,
                                             agent: changes["agent"],
                                             refs: changes["refs"],
                                             shot: shot_from(changes))
            end

            json(described(id, store.read(id)))
        end

        # What has been done about a report. Its own route as well as a
        # field of the report, because a client following work in
        # progress asks for this and nothing else.
        get "/reports/:id/journal" do
            id = params[:id]
            report!(id)
            entries = store.journal(id)
            json({ "count" => entries.size, "entries" => entries })
        end

        # Append a line to the trail. Requires `write: true` -- writing
        # into somebody's record of their own defect is a write, even
        # though it changes nothing about the report itself.
        post "/reports/:id/journal" do
            id = params[:id]
            allowed!("journal")
            report!(id)

            note = body_params["note"].to_s
            fail_with(422, "a journal entry needs a note") if note.strip.empty?

            entry = record!(id, note, by: remote_user,
                                      agent: body_params["agent"],
                                      refs: body_params["refs"],
                                      shot: shot_from(body_params))
            json(entry, status: 201)
        end

        # Whitelisted, because the name is a path component -- and the
        # screenshot is the reason this route exists: an agent looking at
        # a visual defect wants the picture, not a description of it.
        get "/reports/:id/file/:name" do
            id, name = params.values_at(:id, :name)
            fail_with(404, "no such report: #{id}") unless
                id.match?(Store::ID)

            type = Store.file_type(name)
            fail_with(404, "not servable: #{name}") if type.nil?

            path = store.dir_for(id) / name
            fail_with(404, "no such file: #{name}") unless path.exist?

            # A stored file never changes, so this is a 304 for every
            # client that asks twice -- and a screenshot is the largest
            # thing here by an order of magnitude.
            last_modified path.mtime
            etag "#{path.size}-#{path.mtime.to_i}"

            content_type type
            path.binread
        end

        post "/reports/:id/state" do
            id = params[:id]
            allowed!("state")
            report!(id)

            state = body_params["state"]
            unless Store::STATES.include?(state)
                fail_with(422, "no such state: #{state.inspect} " \
                               "(#{Store::STATES.join(", ")})")
            end

            store.mark(id, state, by: remote_user,
                                  agent: body_params["agent"])
            json(described(id, store.read(id)))
        end

        post "/reports/:id/archive" do
            id = params[:id]
            allowed!("archive")
            report!(id)

            wanted = body_params.fetch("archived", true)
            store.archive(id, yes: truthy(wanted), by: remote_user,
                              agent: body_params["agent"])
            json(described(id, store.read(id)))
        end

        # Deliberately absent: delete. It is the one operation with
        # nothing behind it, and an interface a program drives is the
        # last place to put it. The review UI asks twice; that is where
        # it stays.
        #
        # Answered rather than left to the 404, because a client that
        # tried DELETE has guessed something reasonable and deserves the
        # actual reason -- with an Allow header, which is what a program
        # reads.
        delete "/reports/:id" do
            response.headers["Allow"] = "GET, PATCH"
            fail_with(405, "reports are not deleted through this " \
                           "interface; the review UI asks twice and does it")
        end

        helpers do
            # Where a report stands is one permission; what has been
            # said about it is another. Changing a state or archiving
            # decides the first and can be wrong in a way somebody has
            # to undo; adding to the journal only lengthens the second,
            # and nothing there can be edited or removed.
            GRANTS = {
                "journal" => "write in a report's journal",
                "archive" => "archive a report",
                "state"   => "set a report's state"
            }.freeze

            # One question, asked of what the request is trying to do
            # rather than of the route it came in on: a PATCH carrying
            # only a note wants the journal grant, and the same PATCH
            # with a state wants that one.
            def allowed!(grant)
                return if api["allows"].include?(grant)

                fail_with(403, "this endpoint may not " \
                               "#{GRANTS.fetch(grant)} " \
                               "(api.write in the deployment config lists " \
                               "what it may: #{Config::API_GRANTS.join(", ")})")
            end

            # False in the spellings a form post and a JSON body each
            # arrive in; anything else, including an absent value, is
            # yes. Asking to archive is the reason to send the request.
            def truthy(value) = ![false, "false", "0", 0].include?(value)

            # The report itself never changes after it is filed, so what
            # a client would notice is the two markers beside it -- and
            # the values, not their mtimes: mtime has one second of
            # resolution, and a report marked fixed a moment after it
            # was read would have carried the same tag and answered 304
            # to somebody waiting for exactly that.
            def report_etag(id)
                "#{id}-#{store.state(id)}-" \
                    "#{store.archived?(id) ? 1 : 0}-#{store.journal(id).size}"
            end

            # Where this app is mounted, as the client sees it.
            # SCRIPT_NAME and nothing else: the Prefix middleware has
            # already folded the proxy's stripped mount into it, and
            # URLMap appended /api on top. Reading the raw header here
            # as well lost that segment -- behind a vhost the openapi
            # link pointed at <mount>/openapi.json, one level too high.
            def mounted(path)
                "#{request.script_name.to_s.chomp("/")}#{path}"
            end

            # The orientation a client that knows nothing reads first,
            # so a route missing from here is a route agents never
            # find; test/openapi_test.rb holds it to the schema.
            def routes_description
                {
                    "GET /sites"    => "where reports may come from, " \
                                       "and how many are open for each",
                    "GET /reports"  => "id, at, site, state, archived, " \
                                       "channels, summary",
                    "GET /reports/:id"            => "the report as " \
                                                     "filed, its state " \
                                                     "and its journal",
                    "GET /reports/:id/journal"    => "what has been " \
                                                     "done about it",
                    "GET /reports/:id/file/:name" =>
                        "#{Store::SERVABLE.keys.join(", ")}, shot-N.webp",
                    "GET /openapi.json"           => "the full schema, " \
                                                     "a note to an agent " \
                                                     "on every operation",
                    "PATCH /reports/:id"          => "state, archived, " \
                                                     "note, image -- any " \
                                                     "of them, at once",
                    "POST /reports/:id/journal"   =>
                        "{\"note\": \"what you did\"}",
                    "POST /reports/:id/state"     => "{\"state\": \"fixed\"}",
                    "POST /reports/:id/archive"   => "{\"archived\": true}",
                    "DELETE /reports/:id"         => "never -- deleting " \
                                                     "stays in the review " \
                                                     "UI, which asks twice"
                }
            end
        end
    end
end
