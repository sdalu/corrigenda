# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

module DebugFeedback
    # One directory per report under <root>/YYYY/MM/<id>, plus an
    # append-only index.jsonl for listing. The index line is written
    # LAST, so a half-written report is never listed. No database: the
    # volume is tens per month and this survives a year of neglect.
    class Store
        INDEX  = "index.jsonl"
        STATES = %w[open fixed wontfix].freeze

        attr_reader :root

        def initialize(root)
            @root = Pathname(root)
        end

        # Sortable, readable, no gem: the date prefix is also how a
        # report is located again without consulting the index.
        def self.generate_id(at) =
            "#{at.strftime('%Y%m%dT%H%M%S')}Z-#{SecureRandom.hex(4)}"

        def dir_for(id)
            raise StorageError, "bad id: #{id}" unless id.match?(/\A\d{8}T/)

            @root / id[0, 4] / id[4, 2] / id
        end

        def save(document, files: {}, reporter: nil)
            at  = Time.now.utc
            id  = self.class.generate_id(at)
            dir = dir_for(id)
            FileUtils.mkdir_p(dir)
            (dir / "report.json").write(JSON.pretty_generate(document))
            files.each { |name, bytes| (dir / name).binwrite(bytes) }
            (dir / "state").write("open\n")
            append_index(index_entry(document, id:, at:, reporter:))
            id
        end

        def read(id)
            file = dir_for(id) / "report.json"
            file.exist? ? JSON.parse(file.read) : nil
        end

        def files(id)
            dir = dir_for(id)
            return [] unless dir.exist?

            dir.children.map { it.basename.to_s }.sort
        end

        def state(id)
            file = dir_for(id) / "state"
            file.exist? ? file.read.strip : "open"
        end

        def mark(id, value)
            unless STATES.include?(value)
                raise StorageError, "unknown state: #{value}"
            end

            (dir_for(id) / "state").write("#{value}\n")
        end

        # Newest first. Reads the state file per entry, which is cheap at
        # this volume and keeps the index immutable.
        def entries(limit: 100)
            index = @root / INDEX
            return [] unless index.exist?

            index.readlines.last(limit).reverse.map do |line|
                entry = JSON.parse(line)
                entry.merge("state" => state(entry.fetch("id")))
            end
        end

        private

        def index_entry(document, id:, at:, reporter:)
            page = document.fetch("page", {})
            {
                "id"       => id,
                "at"       => at.iso8601,
                "type"     => document["type"],
                "site"     => page["site"],
                "url"      => page["url"],
                "summary"  => document["message"].to_s.lines.first.to_s.strip,
                "reporter" => reporter
            }
        end

        def append_index(entry)
            FileUtils.mkdir_p(@root)
            (@root / INDEX).open("a") { it.puts(JSON.generate(entry)) }
        end
    end
end
