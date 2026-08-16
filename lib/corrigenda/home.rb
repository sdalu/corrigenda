# frozen_string_literal: true

require "json"

require "sinatra/base"

require_relative "../corrigenda"
require_relative "prefix"

module Corrigenda
    # What you get when you open the mount point itself: the bookmarklet
    # that loads the widget, and enough state to tell whether the thing
    # is working before you go looking for a bug that is not there.
    class Home < Sinatra::Base
        configure do
            set :views, File.expand_path("../../views", __dir__)
            set :erb, escape_html: true
            set :feedback_config, Config.load
            set :show_exceptions, false
            set :host_authorization, { permitted_hosts: [] }
            set :absolute_redirects, false
        end

        helpers MountPath

        # Built by extension/build, which is not run on deploy: an
        # absent package is a page that says so rather than a broken
        # download.
        PACKAGES = File.expand_path("../../extension/dist", __dir__)

        # The widget itself. It used to live in Common/js and be served
        # as a static file by every vhost; serving it from here keeps
        # the client and the endpoint that receives its reports in one
        # repository, versioned together, so a client can never be newer
        # than the service reading its payloads.
        CLIENT = File.expand_path("../../client/corrigenda.js", __dir__)

        # The add-on's icon, doubling as the service's. One drawing for
        # the toolbar button and the browser tab: they are the same tool,
        # and a second drawing is a second thing to keep in step.
        ICON = File.expand_path("../../extension/icon.svg", __dir__)

        # The agent manual. Served from the checkout the service runs
        # from, so the copy an agent fetches is definitionally the
        # version of the service it is talking to.
        MANUAL = File.expand_path("../../AGENT-USAGE.md", __dir__)

        # Swagger UI, vendored rather than fetched from a CDN: this page
        # is behind a login, and a viewer that pulls a megabyte and a
        # half from somebody else's server on every visit is a third
        # party watching an authenticated page. See assets/swagger/.
        VIEWER_DIR = File.expand_path("../../assets/swagger", __dir__)

        VIEWER = {
            "swagger-ui-bundle.js" => "application/javascript; charset=utf-8",
            "swagger-ui.css"       => "text/css; charset=utf-8"
        }.freeze

        helpers do
            def store
                @store ||= Store.new(settings.feedback_config.store_path)
            end

            # A signed .xpi if one has been made, the plain zip
            # otherwise. The difference is the whole install story on
            # Firefox: a signed package installs in one click and stays
            # installed, an unsigned one can only be loaded as a
            # temporary add-on and is gone at the next restart.
            def package(target)
                [File.join(PACKAGES, "#{target}.xpi"),
                 File.join(PACKAGES, "#{target}.zip")].find { File.exist?(it) }
            end

            def signed?(target) = package(target).to_s.end_with?(".xpi")

            # Read rather than repeated: the id is the one string in
            # the manifest that must never change once a package has
            # been signed, and a page quoting a stale copy of it is
            # how it gets changed.
            def addon_id
                manifest = File.expand_path(
                    "../../extension/manifest.firefox.json", __dir__)
                JSON.parse(File.read(manifest))
                    .dig("browser_specific_settings", "gecko", "id")
            rescue Errno::ENOENT, JSON::ParserError
                nil
            end

            # The add-on's version, which is its own and not this
            # service's: it is installed rather than served, so a browser
            # may be carrying any of them, and the only honest answer to
            # "which build is this download" is the one in the build.
            def package_version(target)
                manifest = File.join(PACKAGES, target, "manifest.json")
                return nil unless File.exist?(manifest)

                JSON.parse(File.read(manifest))["version"]
            rescue JSON::ParserError
                nil
            end
        end

        # How to make the download install for good rather than for one
        # session. Written for whoever runs this service, which the box
        # on the front page is not: it tells a reader their install is
        # temporary, and this says what to do about it.
        get "/icon.svg" do
            cache_control :public, max_age: 86_400
            send_file ICON, type: "image/svg+xml"
        end

        get "/signing" do
            erb :signing, locals: { root: File.expand_path("../..", __dir__) }
        end

        get "/" do
            config = settings.feedback_config
            erb :home, locals: {
                count: store.count,
                latest: store.entries(limit: 1).first,
                store_path: config.store_path,
                socket: config.socket,
                sites: config.sites,
                origins: config.origins,
                endpoint: config.endpoint,
                packages: %w[firefox chrome].to_h { |target|
                    path = package(target)
                    [target, path && { bytes: File.size(path),
                                       signed: signed?(target),
                                       version: package_version(target) }]
                }
            }
        end

        # The one route on this service that is not staff-only: every
        # page that injects the widget fetches it, and those pages are
        # public. Apache lets this path through unauthenticated (see
        # deploy/macro-corrigenda.conf); nothing here is a secret —
        # the same file was world-readable under /common/js for months.
        #
        # Cached, but briefly: a stale widget is a widget whose report
        # format the endpoint may no longer read, and five minutes is
        # long enough to spare a busy site the requests while short
        # enough that a fix is everywhere by the time you have finished
        # telling someone about it. send_file adds Last-Modified, so
        # most of those requests answer 304 anyway.
        # The schema, rendered. Only where there is an interface to
        # render: with no `api:` key the endpoint answers 404 to
        # everything, and a viewer of nothing is a page that looks
        # broken rather than one that is switched off.
        get "/apidocs" do
            halt 404, "no API on this deployment\n" unless api_offered?

            @wide = true
            erb :apidocs
        end

        # Vendored, whitelisted by name, and cached hard: they are a
        # third party's release, they do not change between them, and
        # they are the largest thing this service serves.
        get "/apidocs/:asset" do
            halt 404, "no API on this deployment\n" unless api_offered?

            type = VIEWER[params[:asset]]
            halt 404, "no such asset\n" if type.nil?

            cache_control :public, max_age: 31_536_000, immutable: true
            send_file File.join(VIEWER_DIR, params[:asset]), type:
        end

        # llms.txt (llmstxt.org): a small curated markdown file at a
        # mount root, for an agent that arrives knowing only the
        # convention. Generated rather than shipped so it can only say
        # what this deployment's config says — a hand-written copy is a
        # second description of the interface, one config edit away
        # from pointing at a dead route. It stays a pointer: the schema
        # it links to carries the real instructions, one per operation.
        get "/llms.txt" do
            content_type "text/plain; charset=utf-8"

            head = ["# Corrigenda", "",
                    "> A defect-report service: reports about what a page",
                    "> shows, filed with their evidence — the element, the",
                    "> rules that styled it, a screenshot."]

            # This file and the manual are the public half; everything
            # they point at is not. An agent that arrives here with no
            # credentials would otherwise meet a 401 and read it as a
            # wall -- so the file that IS reachable is where the way
            # past it is written. Not in the person's voice: whoever
            # set the agent to work is not the one talking here.
            login = [
                "This file and the manual are readable by anyone; the",
                "interface and the reports are not. If a request comes",
                "back 401, use the credentials whoever set you to work",
                "gave you — and if you were given none, ask them rather",
                "than stopping."
            ]

            body =
                if api_offered?
                    ["> The JSON interface under #{mount("/api/")}",
                     "> describes itself: start with a GET there — it says",
                     "> what routes exist and what this deployment allows.",
                     "",
                     *login,
                     "",
                     "## Docs",
                     "",
                     "- [usage.md](#{mount("/agent/usage.md")}): " \
                     "the protocol for working reports, written for you",
                     "- [openapi.json](#{mount("/api/openapi.json")}): " \
                     "the interface in full, with a note addressed " \
                     "to an AI on every operation"]
                else
                    ["> Its JSON interface is switched off here: reports",
                     "> are read by people, in the review UI."]
                end

            (head + body).join("\n") << "\n"
        end

        # The protocol the landing page's prompt no longer restates:
        # written once, in AGENT-USAGE.md, and handed out by the
        # service so an agent with only the socket needs no checkout.
        #
        # Under /agent/ because that is where anything written FOR one
        # belongs, and there will be more of it than this -- a state
        # vocabulary, worked examples, per-site instructions. llms.txt
        # is the exception that stays at the mount: it is a convention
        # with a fixed spelling, and a client that knows it looks there
        # and nowhere else. So the index is at the root and what it
        # indexes is in the directory, which is the usual shape.
        get "/agent/usage.md" do
            send_file MANUAL, type: "text/plain; charset=utf-8"
        end

        get "/corrigenda.js" do
            cache_control :public, max_age: 300
            send_file CLIENT, type: "application/javascript; charset=utf-8"
        end

        # The package itself. Named for the browser rather than for the
        # file inside, because that is what the person clicking knows.
        get "/extension/:target" do
            target = params[:target].to_s.sub(/\.(zip|xpi)\z/, "")
            path   = package(target)
            halt 404, "no package built for #{target}" if path.nil?

            # application/x-xpi is what makes Firefox offer to install
            # rather than to save. Served as a zip it is a file in your
            # downloads folder and a puzzled reader.
            #
            # The version goes in the name, out of the package that is
            # being sent rather than out of anything here: a downloads
            # folder collects these, and three files called
            # corrigenda-firefox.zip are three files nobody can tell
            # apart — including the one they are running.
            xpi     = path.end_with?(".xpi")
            version = package_version(target)
            name    = ["corrigenda", target, version].compact.join("-")

            send_file path,
                      filename: "#{name}#{xpi ? ".xpi" : ".zip"}",
                      type: xpi ? "application/x-xpi" : "application/zip"
        end
    end
end
