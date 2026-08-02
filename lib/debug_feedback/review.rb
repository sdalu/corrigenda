# frozen_string_literal: true

require "json"
require "sinatra/base"

require_relative "../debug_feedback"
require_relative "prefix"

module DebugFeedback
    # Read-mostly listing of what has been reported. Behind the same
    # Apache auth as the intake; the only write is the state marker.
    class Review < Sinatra::Base
        SERVABLE = {
            "screenshot.webp" => "image/webp",
            "snapshot.html"   => "text/html",
            "report.json"     => "application/json"
        }.freeze

        configure do
            set :views, File.expand_path("../../views", __dir__)
            set :erb, escape_html: true
            set :feedback_config, Config.load
            set :show_exceptions, false

            # See the note in intake.rb: Sinatra's development default
            # would answer "Host not permitted" to everything Apache
            # proxies here.
            set :host_authorization, { permitted_hosts: [] }

            # Sinatra re-absolutises every redirect against the host
            # it thinks it has, which behind the proxy is the backend
            # and http, not the vhost and https. A path-only Location
            # keeps the browser on the scheme and host it came from.
            set :absolute_redirects, false
        end

        helpers MountPath

        helpers MountPath

        helpers do
            def store = @store ||= Store.new(settings.feedback_config.store_path)

            def find(id)
                document = store.read(id)
                halt 404, "no such report\n" if document.nil?

                document
            end

            # Marks for what a report carried. Each chip is titled and
            # the legend under the table names them in full: the letter
            # is a reminder, not the only way to read it.
            def channels(keys)
                return "—" if keys.nil? || keys.empty?

                CHANNELS.filter_map { |key, mark|
                    next unless keys.include?(key)

                    %(<span class="chip" title="#{key}">#{mark}</span>)
                }.join
            end

            def summarise(entry)
                text = entry["summary"].to_s
                text.empty? ? "(no message)" : text
            end
        end

        get "/" do
            erb :index, locals: { entries: store.entries }
        end

        get "/:id" do
            id = params[:id]
            erb :report, locals: { id:, document: find(id),
                                   files: store.files(id),
                                   state: store.state(id) }
        end

        # Whitelisted, because the name is a path component.
        get "/:id/file/:name" do
            id, name = params.values_at(:id, :name)
            type     = SERVABLE[name]
            halt 404, "not servable\n" if type.nil?

            path = store.dir_for(id) / name
            halt 404, "no such file\n" unless path.exist?

            content_type type
            path.binread
        end

        post "/:id/state" do
            id = params[:id]
            find(id)
            store.mark(id, params[:state])
            redirect to("/#{id}", false)
        rescue StorageError => e
            halt 400, "#{e.message}\n"
        end
    end
end
