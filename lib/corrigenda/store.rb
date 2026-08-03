# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

module Corrigenda
    # One directory per report under <root>/YYYY/MM/<id>, plus an
    # append-only index.jsonl for listing. The index line is written
    # LAST, so a half-written report is never listed. No database: the
    # volume is tens per month and this survives a year of neglect.
    class Store
        INDEX  = "index.jsonl"
        STATES = %w[open fixed wontfix].freeze

        # Archiving is not a fourth state: a report is archived *and*
        # fixed, or archived and wontfix. What happened to the defect and
        # whether anyone still wants it in front of them are two
        # questions, so they are two files.
        ARCHIVE = "archived"

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

        def archived?(id) = (dir_for(id) / ARCHIVE).exist?

        def archive(id, yes: true)
            dir = dir_for(id)
            raise StorageError, "no such report: #{id}" unless dir.exist?

            file = dir / ARCHIVE
            if yes
                file.write("")
            elsif file.exist?
                file.delete
            end

            yes
        end

        # Gone, not hidden: the directory and the index line both. The
        # index is otherwise append-only, so this is the one operation
        # that rewrites it -- through a temporary file and a rename, so a
        # reader sees either the old index or the new one, never half of
        # one.
        def destroy(id)
            dir = dir_for(id)
            raise StorageError, "no such report: #{id}" unless dir.exist?

            FileUtils.rm_rf(dir)
            forget(id)
            id
        end

        def count
            index = @root / INDEX
            index.exist? ? index.readlines.size : 0
        end

        # Newest first. Reads the state and archive markers per entry,
        # which is cheap at this volume and keeps the index immutable.
        #
        # archived: false is the working list, true the archive, nil
        # both. The filter runs before the limit -- filtering after it
        # would answer "the archive" with whichever of the last hundred
        # reports happened to be archived.
        def entries(limit: 100, archived: false)
            index = @root / INDEX
            return [] unless index.exist?

            index.readlines.reverse.filter_map { |line|
                entry = JSON.parse(line)
                id    = entry.fetch("id")
                mark  = archived?(id)
                next if !archived.nil? && mark != archived

                entry.merge("state" => state(id), "archived" => mark)
            }.first(limit)
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
                "reporter" => reporter,
                "channels" => document.fetch("capture", {}).select { |_, on| on }.keys
            }
        end

        # Rewritten rather than marked: a deleted report should leave
        # nothing behind, and a tombstone in the index is something.
        def forget(id)
            index = @root / INDEX
            return unless index.exist?

            kept = index.readlines.reject { JSON.parse(it).fetch("id") == id }
            temp = @root / "#{INDEX}.new"
            temp.write(kept.join)
            temp.rename(index.to_s)
        end

        def append_index(entry)
            FileUtils.mkdir_p(@root)
            (@root / INDEX).open("a") { it.puts(JSON.generate(entry)) }
        end
    end
end
