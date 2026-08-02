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

        helpers MountPath

        helpers do
            def store = @store ||= Store.new(settings.feedback_config.store_path)
        end

        get "/" do
            config = settings.feedback_config
            erb :home, locals: {
                count: store.count,
                latest: store.entries(limit: 1).first,
                store_path: config.store_path,
                sites: config.sites
            }
        end
    end
end
