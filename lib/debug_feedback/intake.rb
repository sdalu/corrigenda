# frozen_string_literal: true

require "json"
require "sinatra/base"
require "stringio"
require "zlib"

require_relative "../debug_feedback"

module DebugFeedback
    # POST target for the widget. Apache authenticates in front of this
    # (see DEBUG-FEEDBACK.md), so there is no anti-abuse machinery here — the
    # limits below are sanity bounds, not spam controls.
    class Intake < Sinatra::Base
        GZIP_MAGIC = "\x1F\x8B".b
        ATTACHMENTS = {
            "screenshot" => [:screenshot, "screenshot.webp"],
            "snapshot"   => [:snapshot,   "snapshot.html"]
        }.freeze

        configure do
            set :feedback_config, Config.load
            set :show_exceptions, false

            # Sinatra restricts Host to localhost and friends whenever the
            # environment is development, which is what it is here: there
            # is no RACK_ENV to set it otherwise. Apache proxies with the
            # vhost's own Host header, so every real request would be
            # answered "Host not permitted".
            #
            # An empty list disables the check. That is right for this
            # deployment rather than lazy: the only way in is a unix socket
            # readable by Apache's group, so Apache -- not this app --
            # decides which vhosts may reach it, and nothing here routes or
            # builds absolute URLs from Host.
            set :host_authorization, { permitted_hosts: [] }
        end

        helpers do
            def config = settings.feedback_config

            def store = @store ||= Store.new(config.store_path)

            # REMOTE_USER is a server variable, not a header, so it does
            # NOT cross the proxy: Apache re-sends it as X-Remote-User
            # with `RequestHeader set`, which overwrites anything a
            # client tried to put there. The fallback covers running the
            # app without a proxy in front.
            def reporter
                request.env["HTTP_X_REMOTE_USER"] || request.env["REMOTE_USER"]
            end

            def bail(code, message)
                halt code, { "content-type" => "application/json" },
                     JSON.generate(error: message)
            end

            def oversize?
                length = request.content_length
                !length.nil? && length.to_i > config.max_body
            end

            # A gzip magic number is enough to know; no custom header.
            def gunzip(raw)
                return raw unless raw.start_with?(GZIP_MAGIC)

                limit = config.max_report
                data  = Zlib::GzipReader.new(StringIO.new(raw)).read(limit + 1)
                bail(413, "report too large decompressed") if too_big?(data, limit)
                data
            end

            def too_big?(data, limit) = data.nil? || data.bytesize > limit

            def part(name, kind)
                value = params[name]
                limit = config.max_for(kind)
                data  = case value
                        when Hash   then value[:tempfile]&.read(limit + 1)
                        when String then value
                        end
                return nil if data.nil? || data.empty?

                bail(413, "#{name} too large") if too_big?(data, limit)
                data
            end

            def read_report
                raw = if request.media_type == "application/json"
                          request.body.read(config.max_report + 1)
                      else
                          part("report", :report)
                      end
                bail(400, "no report") if raw.nil? || raw.empty?
                bail(413, "report too large") if too_big?(raw, config.max_report)
                JSON.parse(gunzip(raw))
            rescue JSON::ParserError
                bail(400, "report is not JSON")
            end

            def attachments
                ATTACHMENTS.filter_map do |name, (kind, filename)|
                    bytes = part(name, kind)
                    bytes.nil? ? nil : [filename, bytes]
                end.to_h
            end
        end

        get "/health" do
            content_type :json
            JSON.generate(status: "ok")
        end

        post "/" do
            bail(413, "payload too large") if oversize?
            document = DebugFeedback.validate(read_report)
            site     = document.dig("page", "site")
            bail(403, "unknown site: #{site}") unless config.site_allowed?(site)

            id = store.save(document, files: attachments, reporter:)
            status 201
            content_type :json
            JSON.generate(id:, review: "/review/#{id}")
        rescue PayloadError => e
            bail(422, e.message)
        end
    end
end
