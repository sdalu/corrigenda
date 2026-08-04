# frozen_string_literal: true

require "json"
require "sinatra/base"

require_relative "../corrigenda"
require_relative "prefix"

module Corrigenda
    # Read-mostly listing of what has been reported. Behind the same
    # Apache auth as the intake; the only write is the state marker.
    class Review < Sinatra::Base
        # How many rows a list shows before it stops and says so. The
        # same hundred /api/reports answers with, so the two interfaces
        # cut a long store at the same place.
        LISTED = 100

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

        helpers MountPath, RemoteUser

        helpers do
            def store
                @store ||= Store.new(settings.feedback_config.store_path)
            end

            # To the minute, without the T and the Z, which are
            # punctuation for a machine; the full stamp stays in the
            # title and datetime attributes for whoever wants it exact.
            def short_stamp(at) = at.to_s[0, 16].tr("T", " ")

            # A report's URL becomes a link a reviewer clicks, so only
            # a web address gets an href; anything else stays words.
            # The intake now refuses other schemes too, but reports
            # filed before that guard still render.
            def page_href(url)
                url if url.to_s.match?(%r{\Ahttps?://}i)
            end

            # Where a press should leave you. From a report's own page,
            # back to it; from the listing, back to the listing you were
            # reading, archive or not — being thrown into a report you
            # did not open is the thing that made triaging from the list
            # not worth doing.
            #
            # Only `from` says it. The archive form's `archived` is what
            # it wants done, not where it came from, and reading the way
            # back off that sent anyone who archived a report from the
            # working list into the archive.
            def back_to(id)
                case params[:from]
                when "list"    then to("/", false)
                when "archive" then to("/?archived=1", false)
                else                to("/#{id}", false)
                end
            end

            def find(id)
                halt 404, "no such report\n" unless id.match?(Store::ID)

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

            # How many rows to show, from the URL. `all` lifts the cut
            # entirely; anything that is not a positive number falls
            # back to the default rather than being refused, which is
            # how /api/reports reads the same parameter — a hand-typed
            # ?limit= should not be answered with an error page, and
            # ?limit=0 is a typo, not a request for an empty list.
            def listing_limit
                return nil if params[:limit] == "all"

                asked = Integer(params[:limit].to_s, exception: false)
                asked&.positive? ? asked : LISTED
            end
        end

        # Two lists, the same table: what is in front of you, and what has
        # been put away. Archived reports are not a different kind of
        # thing and do not get a different page.
        # Wide, like the schema viewer and unlike a report: this page
        # is a table of eight columns, and a URL and a summary both
        # want room. At the prose width they wrapped to four lines
        # each and the rows were twice as tall as they needed to be.
        #
        # Unlimited from the store, then counted, then cut — the same
        # order /api/reports takes, and for the same reason one level
        # further on: a limit applied first makes every number measured
        # after it a number about a window nobody chose. That is what
        # made "Archived (100)" the answer for an archive of four
        # hundred, and a count in a link is read as a fact.
        get "/" do
            @wide = true
            archived = params[:archived] == "1"
            limit    = listing_limit
            entries  = store.entries(limit: nil, archived:)

            erb :index, locals: {
                entries: limit ? entries.first(limit) : entries,
                total: entries.size,
                archived:,
                other: store.entries(limit: nil, archived: !archived).size
            }
        end

        get "/:id" do
            id = params[:id]
            erb :report, locals: { id:, document: find(id),
                                   files: store.files(id),
                                   state: store.state(id),
                                   archived: store.archived?(id),
                                   journal: store.journal(id) }
        end

        # Whitelisted, because the name is a path component.
        get "/:id/file/:name" do
            id, name = params.values_at(:id, :name)
            halt 404, "no such report\n" unless id.match?(Store::ID)

            type = Store.file_type(name)
            halt 404, "not servable\n" if type.nil?

            path = store.dir_for(id) / name
            halt 404, "no such file\n" unless path.exist?

            content_type type
            path.binread
        end

        post "/:id/state" do
            id = params[:id]
            find(id)
            store.mark(id, params[:state], by: remote_user)
            redirect back_to(id)
        rescue StorageError => e
            halt 400, "#{e.message}\n"
        end

        # Out of the working list and back into it. Nothing is lost
        # either way, which is why this needs no confirming.
        post "/:id/archive" do
            id = params[:id]
            find(id)
            store.archive(id, yes: params[:archived] != "0",
                              by: remote_user)
            redirect back_to(id)
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
