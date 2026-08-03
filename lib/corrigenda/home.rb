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
            def store = @store ||= Store.new(settings.feedback_config.store_path)

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
            xpi = path.end_with?(".xpi")
            send_file path,
                      filename: "corrigenda-#{target}#{xpi ? '.xpi' : '.zip'}",
                      type: xpi ? "application/x-xpi" : "application/zip"
        end
    end
end
