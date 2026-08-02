# frozen_string_literal: true

require "sinatra/base"

require_relative "../debug_feedback"
require_relative "prefix"

module DebugFeedback
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

        helpers do
            def store = @store ||= Store.new(settings.feedback_config.store_path)

            def package(target)
                path = File.join(PACKAGES, "#{target}.zip")
                File.exist?(path) ? path : nil
            end
        end

        get "/" do
            config = settings.feedback_config
            erb :home, locals: {
                count: store.count,
                latest: store.entries(limit: 1).first,
                store_path: config.store_path,
                sites: config.sites,
                packages: %w[firefox chrome].to_h { [it, package(it)&.then { File.size(it) }] }
            }
        end

        # The package itself. Named for the browser rather than for the
        # file inside, because that is what the person clicking knows.
        get "/extension/:target" do
            target = params[:target].to_s.sub(/\.(zip|xpi)\z/, "")
            path   = package(target)
            halt 404, "no package built for #{target}" if path.nil?

            send_file path, filename: "debug-feedback-#{target}.zip",
                            type: "application/zip"
        end
    end
end
