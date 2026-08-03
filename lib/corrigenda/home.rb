# frozen_string_literal: true

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
                                       signed: signed?(target) }]
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
