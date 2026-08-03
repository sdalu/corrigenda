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

        # What has been done about the report, appended a line at a time.
        JOURNAL = "journal.jsonl"

        # A picture belonging to one line of that trail rather than to
        # the report: what the page looked like after the work, beside
        # what it looked like when somebody complained. Numbered in the
        # order they arrive and never reused, so a line's picture stays
        # that line's picture when the next one is added.
        SHOT = /\Ashot-\d+\.(webp|png|jpg)\z/
        SHOT_TYPES = { "image/webp" => "webp", "image/png" => "png",
                       "image/jpeg" => "jpg" }.freeze

        # Room for a full-page capture of a long page, and no room for
        # somebody's holiday video.
        MAX_SHOT = 8 * 1024 * 1024

        # Kept by this class beside a report, rather than filed with it.
        MARKERS = ["state", ARCHIVE, JOURNAL].freeze

        # What a journal picture may be served as, or nil for a name
        # that is not one. The naming is this class's, so the answer is
        # too — both the review UI and the API ask.
        def self.shot_type(name)
            ext = name.to_s[SHOT, 1]
            return nil if ext.nil?

            ext == "jpg" ? "image/jpeg" : "image/#{ext}"
        end

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

        def mark(id, value, by: nil, agent: nil)
            unless STATES.include?(value)
                raise StorageError, "unknown state: #{value}"
            end

            was = state(id)
            (dir_for(id) / "state").write("#{value}\n")
            unless was == value
                record(id, "#{was} → #{value}", kind: "state", by:, agent:)
            end

            value
        end

        def archived?(id) = (dir_for(id) / ARCHIVE).exist?

        def archive(id, yes: true, by: nil, agent: nil)
            dir = dir_for(id)
            raise StorageError, "no such report: #{id}" unless dir.exist?

            was  = archived?(id)
            file = dir / ARCHIVE
            if yes
                file.write("")
            elsif file.exist?
                file.delete
            end

            unless was == yes
                record(id, yes ? "archived" : "back in the working list",
                       kind: "archive", by:, agent:)
            end

            yes
        end

        # What has been done about a report, in the order it was done.
        # Appended and never rewritten: a trail that can be edited is a
        # trail nobody has to believe, and the whole point of writing
        # down what an agent changed is that a person can check it.
        #
        # The state and the archive marker say where a report stands;
        # this says how it got there, and it is the only place anything
        # here keeps prose about work done. Nothing is deleted from it
        # short of deleting the report.
        def journal(id)
            file = dir_for(id) / JOURNAL
            return [] unless file.exist?

            file.readlines.filter_map { JSON.parse(it) rescue nil }
        end

        # `by` is who the server knows the caller to be -- Apache's
        # authenticated user, or whoever runs a task on the host. `agent`
        # is what the caller says it is, which is not the same fact and
        # is kept apart from it: a program naming itself is useful, and
        # it is not identification.
        # `shot` is a picture for this line: { type:, bytes: }. It is
        # written before the line is, so a journal never names a file
        # that is not there.
        def record(id, note, kind: "note", by: nil, agent: nil, refs: nil,
                   shot: nil)
            dir = dir_for(id)
            raise StorageError, "no such report: #{id}" unless dir.exist?

            text = note.to_s.strip
            raise StorageError, "an empty note records nothing" if text.empty?

            entry = { "at" => Time.now.utc.iso8601, "kind" => kind,
                      "note" => text }
            entry["by"]    = by    unless by.to_s.empty?
            entry["agent"] = agent unless agent.to_s.empty?
            entry["refs"]  = Array(refs) unless Array(refs).empty?
            entry["shot"]  = write_shot(dir, shot) unless shot.nil?

            (dir / JOURNAL).open("a") { it.puts(JSON.generate(entry)) }
            entry
        end

        # Every picture a journal line carries, oldest first. The report
        # was filed with `screenshot.webp`; these came later.
        def shots(id) = files(id).select { it.match?(SHOT) }

        # What was filed with the report, without the markers this keeps
        # beside it: state, the archive flag, the journal.
        def attachments(id) = files(id) - MARKERS

        # Gone, not hidden: the directory and the index line both. The
        # index is otherwise append-only, so this is the one operation
        # that rewrites it -- through a temporary file and a rename, so a
        # reader sees either the old index or the new one, never half of
        # one.
        def destroy(id)
            dir = dir_for(id)
            raise StorageError, "no such report: #{id}" unless dir.exist?

            FileUtils.rm_rf(dir)
            forget([id])
            prune_empty(id)
            id
        end

        def count
            index = @root / INDEX
            index.exist? ? index.readlines.size : 0
        end

        # Age is read off the id, not off the index: the id is minted
        # from the filing time and travels with the directory, so a
        # report whose index line was lost is still datable and a purge
        # never depends on the one file it is about to rewrite.
        def self.filed_at(id)
            unless id.match?(/\A\d{8}T\d{6}Z/)
                raise StorageError, "bad id: #{id}"
            end

            Time.utc(id[0, 4].to_i, id[4, 2].to_i, id[6, 2].to_i,
                     id[9, 2].to_i, id[11, 2].to_i, id[13, 2].to_i)
        end

        # When it was archived is the marker's own mtime: `archive`
        # writes that file at the moment somebody decided they were done
        # looking at the report, so the fact was already on disk and no
        # format had to change to keep it.
        def archived_at(id)
            file = dir_for(id) / ARCHIVE
            file.exist? ? file.mtime.utc : nil
        end

        # Every report on disk, oldest first -- the directories rather
        # than the index, because a directory the index lost should age
        # out like any other and not become a thing only `du` knows
        # about.
        def ids
            @root.glob("[0-9][0-9][0-9][0-9]/[0-9][0-9]/*")
                 .select(&:directory?).map { it.basename.to_s }.sort
        end

        # What a purge would take and under which rule. Separate from
        # taking it: a deletion nobody can explain first is a deletion
        # nobody will authorise, and this is the one operation here with
        # nothing behind it.
        def expired(rules, now: Time.now.utc)
            return [] if rules.nil? || rules.empty?

            ids.filter_map { verdict(it, rules, now) }
        end

        # Gone, with the index rewritten once rather than once per
        # report: `destroy` rewrites it every time, which is fine for the
        # one report somebody deleted by hand and quadratic for a year of
        # them.
        def purge(rules, now: Time.now.utc)
            going = expired(rules, now:)
            going.each { FileUtils.rm_rf(dir_for(it[:id])) }
            forget(going.map { it[:id] })
            going.each { prune_empty(it[:id]) }
            going
        end

        # Newest first. Reads the state and archive markers per entry,
        # which is cheap at this volume and keeps the index immutable.
        #
        # archived: false is the working list, true the archive, nil
        # both. The filter runs before the limit -- filtering after it
        # would answer "the archive" with whichever of the last hundred
        # reports happened to be archived.
        #
        # limit: nil is all of them, for a caller with a filter of its
        # own to apply: the same trap one level up, since anything
        # narrowed after a limit is narrowed within a window it did not
        # choose.
        def entries(limit: 100, archived: false)
            index = @root / INDEX
            return [] unless index.exist?

            found = index.readlines.reverse.filter_map { |line|
                entry = JSON.parse(line)
                id    = entry.fetch("id")
                mark  = archived?(id)
                next if !archived.nil? && mark != archived

                entry.merge("state" => state(id), "archived" => mark)
            }

            limit.nil? ? found : found.first(limit)
        end

        private

        # Numbered from the pictures already on disk rather than from
        # the length of the journal: most lines carry none, and a name
        # counted from lines would be handed out twice.
        def write_shot(dir, shot)
            type  = shot[:type] || shot["type"]
            bytes = shot[:bytes] || shot["bytes"]
            ext   = SHOT_TYPES[type.to_s]
            raise StorageError, "not a picture this keeps: #{type}" if ext.nil?
            raise StorageError, "an empty picture" if bytes.to_s.empty?

            if bytes.bytesize > MAX_SHOT
                raise StorageError, "picture too large: #{bytes.bytesize} " \
                                    "bytes, and #{MAX_SHOT} is the limit"
            end

            name = "shot-#{dir.children.count { it.basename.to_s.match?(SHOT) } + 1}.#{ext}"
            (dir / name).binwrite(bytes)
            name
        end

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

        # archived first: it is the rule about a decision somebody made,
        # where `any` is only about the calendar. A report old enough for
        # both was archived before it was ancient, and that is the truer
        # reason to give.
        def verdict(id, rules, now)
            if (limit = rules["archived"]) && (at = archived_at(id))
                age = age_in_days(at, now)
                return { id:, rule: "archived", days: age } if age >= limit
            end

            if (limit = rules["any"])
                age = age_in_days(self.class.filed_at(id), now)
                return { id:, rule: "any", days: age } if age >= limit
            end

            nil
        end

        def age_in_days(at, now) = ((now - at) / 86_400).floor

        # A month that has been emptied should not stay as a directory
        # for ever. rmdir refuses one with anything still in it, which is
        # exactly the question being asked, so the refusal is the answer
        # rather than an error.
        def prune_empty(id)
            dir = dir_for(id)
            [dir.parent, dir.parent.parent].each do |path|
                path.rmdir
            rescue SystemCallError
                break
            end
        end

        # Rewritten rather than marked: a deleted report should leave
        # nothing behind, and a tombstone in the index is something. Takes
        # a list because a purge is many at once and the file should be
        # rewritten once, not once per report.
        def forget(ids)
            index = @root / INDEX
            return if ids.empty? || !index.exist?

            gone = ids.to_h { [it, true] }
            kept = index.readlines.reject {
                gone.key?(JSON.parse(it).fetch("id"))
            }
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
