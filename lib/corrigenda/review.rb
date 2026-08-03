# frozen_string_literal: true

require "json"
require "sinatra/base"

require_relative "../corrigenda"
require_relative "prefix"

module Corrigenda
    # Read-mostly listing of what has been reported. Behind the same
    # Apache auth as the intake; the only write is the state marker.
    class Review < Sinatra::Base
        # A timestamp and a digest, which is what generate_id makes.
        # Checked here rather than left to the store, whose refusal is an
        # exception and became an Internal Server Error on the way out.
        ID = /\A\d{8}T\d{6}Z-[0-9a-f]{8}\z/

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
                halt 404, "no such report\n" unless id.match?(ID)

                document = store.read(id)
                halt 404, "no such report\n" if document.nil?

                document
            end

            # Marks for what a report carried. Each chip is titled and
            # the legend under the table names them in full: the letter
            # is a reminder, not the only way to read it.
            def channels(keys)
                return "—" if keys.nil? || keys.empty?

                CHANNELS.filter_map { |key, (mark, label)|
                    next unless keys.include?(key)

                    %(<span class="chip" data-channel="#{key}" ) +
                        %(title="#{label}">#{mark}</span>)
                }.join
            end

            def summarise(entry)
                text = entry["summary"].to_s
                text.empty? ? "(no message)" : text
            end
        end

        # Two lists, the same table: what is in front of you, and what has
        # been put away. Archived reports are not a different kind of
        # thing and do not get a different page.
        get "/" do
            archived = params[:archived] == "1"
            erb :index, locals: { entries: store.entries(archived:),
                                  archived:,
                                  other: store.entries(archived: !archived).size }
        end

        get "/:id" do
            id = params[:id]
            erb :report, locals: { id:, document: find(id),
                                   files: store.files(id),
                                   state: store.state(id),
                                   archived: store.archived?(id) }
        end

        # Whitelisted, because the name is a path component.
        get "/:id/file/:name" do
            id, name = params.values_at(:id, :name)
            halt 404, "no such report\n" unless id.match?(ID)

            type = SERVABLE[name]
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

        # Out of the working list and back into it. Nothing is lost
        # either way, which is why this needs no confirming.
        post "/:id/archive" do
            id = params[:id]
            find(id)
            store.archive(id, yes: params[:archived] != "0")
            redirect to("/#{id}", false)
        rescue StorageError => e
            halt 400, "#{e.message}\n"
        end

        # Asked twice, and the second time on a page of its own. There is
        # no undo: the directory goes, the screenshot with it, and the
        # index line that would have said it ever existed. A confirm
        # step in the browser would need script; this needs none, works
        # the same everywhere, and shows what is about to go.
        post "/:id/delete" do
            id = params[:id]
            document = find(id)

            unless params[:confirm] == "yes"
                halt erb(:delete, locals: { id:, document:,
                                            files: store.files(id),
                                            archived: store.archived?(id) })
            end

            store.destroy(id)
            redirect to("/", false)
        rescue StorageError => e
            halt 400, "#{e.message}\n"
        end
    end
end
