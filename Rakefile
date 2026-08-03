# frozen_string_literal: true

require "json"
require "shellwords"

require "rake/testtask"

CONFIG   = "deploy/corrigenda.yml"
TEMPLATE = "deploy/corrigenda-template.yml"
MACRO    = "deploy/macro-corrigenda.conf"

Rake::TestTask.new(:test) do |t|
    t.libs    = %w[lib test]
    t.pattern = "test/*_test.rb"
end

# The other half of the suite. The picker, the sanitiser and the CORS
# dance only exist in a browser, so those checks need a browser
# toolchain this repository does not carry and cannot install -- which
# is why they are a task of their own rather than part of `rake test`:
# a checkout without the tools should still have a test suite that
# passes, and be told plainly when it asks for the half it cannot run.
namespace :test do
    desc %(Drive the widget in real browsers (ONLY="widget" runs one))
    task :browser do
        sh(["test/browser/run", *ENV["ONLY"]&.split].shelljoin)
    end
end

# Neither the config nor the macro is in the repository: one names this
# deployment, the other is three of its fields in Apache's syntax. So the
# first thing anything here does is check that a deployment exists.
task :config do
    next if File.exist?(CONFIG)

    abort <<~SAY
        #{CONFIG} does not exist.

            cp #{TEMPLATE} #{CONFIG}
            $EDITOR #{CONFIG}

        Copying is not enough: the endpoint, the sites and the
        directory server in the template are examples. That file
        names this deployment, which is why it is not tracked and
        why nothing here can guess it for you.
    SAY
end

# A file task, so it runs when the config is newer than what was
# generated from it, and not otherwise. `rake macro` forces it.
file MACRO => [CONFIG] do
    sh "deploy/macro"
end

# The two scripts anyone actually runs, reachable the way everything else
# here is. They stay scripts rather than becoming Ruby tasks: ./run is
# what a service manager invokes, and deploy/macro is what Apache's
# configuration depends on. These are doorways, not reimplementations.
desc "Write #{MACRO} from #{CONFIG}"
task macro: :config do
    sh "deploy/macro"
end

namespace :macro do
    desc "Say whether the generated macro matches the config (exit 1 if not)"
    task check: :config do
        sh "deploy/macro --check"
    end

    desc "Print the macro instead of writing it"
    task show: :config do
        sh "deploy/macro --stdout"
    end
end

# Retention is the deployment's business -- how long a report is worth
# keeping is a property of an estate, not of the program -- so it is a
# key in the same config everything else here reads, and absent by
# default. Nothing is ever deleted because the software felt like it.
#
# The library does the deciding (Store#expired, Store#purge); these are
# doorways, and the reason there are two is that this is the one
# operation with nothing behind it: `data:purge:show` is how you find
# out what a rule means before it means it.
def deployment
    $LOAD_PATH.unshift("lib") unless $LOAD_PATH.include?("lib")

    # The umbrella file, not the two pieces: it is what defines the error
    # family the store raises, and rescuing a constant that was never
    # loaded turns a bad id into a NameError and a rake backtrace.
    require "corrigenda"

    # CORRIGENDA_CONFIG the way ./run passes it, so a cron entry can
    # purge the installed deployment's store from a working copy, and so
    # this can be pointed somewhere harmless to see what a rule does.
    file = ENV.fetch("CORRIGENDA_CONFIG", CONFIG)

    unless File.exist?(file)
        abort <<~SAY
            data: #{file} does not exist, so there is no store to work on
            and no rule to work by.

                cp #{TEMPLATE} #{CONFIG}
                $EDITOR #{CONFIG}
        SAY
    end

    config = Corrigenda::Config.load(file)
    [Corrigenda::Store.new(config.store_path), config.retention, file]
rescue ArgumentError => e
    # The config said something about retention that cannot be obeyed.
    # Refusing beats guessing when the guess deletes things.
    abort "data: #{e.message}"
end

# One report to a line, newest first: id, when it was filed, its state,
# what it is about. The summary is the reporter's first line, cut where
# a terminal stops being able to show it.
def listing_line(entry)
    # "2026-08-03T10:48:08Z" -> "2026-08-03 10:48": the seconds are in
    # the id for anyone who needs them.
    at      = entry["at"].to_s[0, 16].tr("T", " ")
    marks   = entry["archived"] ? "archived" : entry["state"]
    summary = entry["summary"].to_s
    summary = "#{summary[0, 39]}…" if summary.length > 40

    format("%-33s %-16s %-9s %-6s %-26s %s",
           entry["id"], at, marks, channel_marks(entry),
           entry["site"], summary)
end

# What the report carried, in one column: the same letters the review UI
# puts on its chips, in the same order every time, with a dot where a
# channel is missing. Fixed positions are the point -- a column you can
# read down tells you which reports have a screenshot without reading a
# word of it.
def channel_marks(entry)
    carried = Array(entry["channels"])
    Corrigenda::CHANNELS.map { |key, (mark, _label)|
        carried.include?(key) ? mark : "·"
    }.join
end

# ID= names one report. Every task that takes one comes through here,
# so the refusal is the same words each time and nothing is done to a
# report before it is known to exist.
def report_for(store, task)
    id = ENV["ID"].to_s.strip
    abort "#{task}: ID=<report> is required (rake data:list to find one)" \
        if id.empty?

    document = begin
        store.read(id)
    rescue Corrigenda::StorageError => e
        abort "#{task}: #{e.message}"
    end

    abort "#{task}: no such report: #{id}" if document.nil?

    [id, document]
end

# One report laid out rather than dumped: the fields somebody reaches
# for, the message in full, then what arrived with it and where it
# sits, since the next question is usually about a screenshot.
def show_report(store, id, document)
    page  = document["page"] || {}
    state = store.archived?(id) ? "#{store.state(id)} (archived)"
                                : store.state(id)

    puts format("%-10s %s", "id",    id)
    puts format("%-10s %s", "state", state)
    puts format("%-10s %s", "type",  document["type"])
    puts format("%-10s %s", "site",  page["site"])
    puts format("%-10s %s", "url",   page["url"])
    puts

    message = document["message"].to_s.strip
    puts message.empty? ? "(no message)" : message
    puts

    puts format("%-10s %s", "files", store.attachments(id).join(", "))
    puts format("%-10s %s", "at",    store.dir_for(id))

    journal = store.journal(id)
    return if journal.empty?

    puts
    journal.each { puts journal_line(it) }
end

# What has been done about it, in the order it was done. The actor and
# the agent are shown together and kept apart, because they are two
# facts: who the server knew, and what the caller called itself.
def journal_line(entry)
    who  = [entry["by"], entry["agent"]].compact.join("/")
    refs = entry["refs"] ? "  (#{entry["refs"].join(", ")})" : ""

    format("%-17s %-8s %-14s %s%s",
           entry["at"].to_s[0, 16].tr("T", " "), entry["kind"],
           who.empty? ? "—" : who, entry["note"], refs)
end

# Whoever is at the terminal, which is the only actor a task has.
def actor = ENV["SUDO_USER"] || ENV["USER"] || ENV["LOGNAME"]

def report_line(entry)
    format("%-33s %s, %d days", entry[:id], entry[:rule], entry[:days])
end

# Named with the file it read, which is not always the deployment's:
# CORRIGENDA_CONFIG may have pointed this somewhere else entirely, and
# quoting the wrong path is how somebody edits a file nothing reads.
def nothing_expires(file)
    puts <<~SAY
        #{file} sets no retention, so nothing expires and this has
        nothing to do. What it would read:

            retention:
                archived: 90     # days after somebody archived it
                any:      365    # days after filing, whatever its state

        Either key alone is a valid rule; a report matching both is
        reported under `archived`, which is the one about a decision
        somebody made rather than about the calendar.
    SAY
end

# The add-on has a version of its own, and deliberately: it is installed
# rather than served, so a browser may be carrying any of them while the
# service is only ever the one it is running. What it must not have is
# two versions -- the Firefox and Chrome packages are one add-on -- and
# the number is written in each manifest because a manifest has to be
# readable on its own, by a browser and by addons-linter, with nothing
# generated first. So: one command that writes both.
MANIFESTS = FileList["extension/manifest.*.json"]

# The two the packages are made for, named here as well as in
# extension/build so a typo is answered by the thing that was asked.
ADDON_TARGETS = %w[firefox chrome].freeze

# One place where the script is called, so a failure reads the same
# whichever task reached it. The script has already said what went
# wrong on its way out; rake's own "aborted!" and a backtrace into this
# file point at the doorway rather than at the failure, and are what
# made a one-line "unknown target: foo" hard to see.
def build_addon(*targets)
    sh(["extension/build", *targets].shelljoin) do |ok, status|
        next if ok

        abort "addon:build: extension/build failed " \
              "(exit #{status&.exitstatus || "?"})"
    end
end

namespace :addon do
    desc %(Show the add-on's version, or raise it (TO="1.2.0"))
    task :version do
        want = ENV["TO"]

        current = MANIFESTS.to_h { |path|
            [path, JSON.parse(File.read(path))]
        }

        if want.nil?
            current.each { |path, m| puts "#{m["version"]}  #{path}" }
            next
        end

        unless want.match?(/\A\d+(\.\d+){1,3}\z/)
            abort "addon:version: #{want.inspect} is not a version " \
                  "(both stores want digits and dots, nothing else)"
        end

        current.each do |path, manifest|
            was = manifest["version"]
            manifest["version"] = want
            File.write(path, JSON.pretty_generate(manifest) + "\n")
            puts "#{path}: #{was} -> #{want}"
        end

        # The packages carry the number; a raised version nobody rebuilt
        # is a download that still says the old one.
        build_addon
    end

    desc "Build the add-on packages (TARGET=firefox builds just one)"
    task :build do
        want = ENV["TARGET"]

        # Checked here rather than left to the script: reaching it means
        # the answer arrives wrapped in a rake failure, which is three
        # lines of machinery around one line of sense.
        if want && !ADDON_TARGETS.include?(want)
            abort "addon:build: no such target #{want.inspect} -- " \
                  "#{ADDON_TARGETS.join(" or ")}, or leave TARGET unset " \
                  "for both"
        end

        build_addon(*want)
    end

    # Signing is what makes the Firefox download install in one click and
    # stay installed; unsigned, it is a temporary add-on that is gone at
    # the next restart. The keys are Mozilla's, personal to whoever runs
    # this, and never in the repository -- so they arrive in the
    # environment and are checked here rather than a third of the way
    # through an upload.
    desc "Sign the Firefox package (needs AMO_JWT_ISSUER and AMO_JWT_SECRET)"
    task :sign do
        missing = %w[AMO_JWT_ISSUER AMO_JWT_SECRET].reject { ENV[it] }

        unless missing.empty?
            abort <<~SAY
                addon:sign: #{missing.join(" and ")} not set.

                    addons.mozilla.org -> Tools -> Manage API keys
                    export AMO_JWT_ISSUER=user:1234567:890
                    export AMO_JWT_SECRET=...

                They are your credentials, not the project's, which is why
                nothing here can supply them. An unlisted submission is
                reviewed automatically and never appears on
                addons.mozilla.org; what comes back is the .xpi this
                service then offers. The /signing page of a running
                service has the whole procedure.
            SAY
        end

        sh "extension/sign"
    end
end

namespace :data do
    # The review UI is behind the proxy and its login; this is the same
    # listing for whoever is already on the host -- and the only way to
    # see what a store holds on the day Apache is the broken thing.
    desc "List the reports (ALL=1 adds archived, ARCHIVED=1 only those)"
    task :list do
        store, = deployment

        # Three answers rather than one flag: the working list is what
        # somebody wants nine times in ten, and the archive is a place
        # you go to on purpose.
        archived = if    ENV["ARCHIVED"] then true
                   elsif ENV["ALL"]      then nil
                   else                       false
                   end

        entries = store.entries(limit: Integer(ENV.fetch("N", 50)),
                                archived:)

        if entries.empty?
            puts case archived
                 when true then "nothing archived"
                 when nil  then "no reports"
                 else "no open reports (ALL=1 to include archived ones)"
                 end
            next
        end

        entries.each { puts listing_line(it) }
        puts "#{entries.size} shown, #{store.ids.size} in the store"
    end

    desc "Show one report in full (ID=<report>)"
    task :show do
        store, = deployment
        id, document = report_for(store, "data:show")
        show_report(store, id, document)
    end

    # Archiving says nothing about the defect -- a report is archived
    # *and* fixed, or archived and wontfix. It only says whether anyone
    # still wants it in front of them, which is why it is its own task
    # rather than a value data:status could take.
    desc "Archive one report, or bring it back (ID=<report> UNDO=1)"
    task :archive do
        store, = deployment
        id, = report_for(store, "data:archive")

        back = !ENV["UNDO"].nil?
        store.archive(id, yes: !back, by: actor, agent: ENV["AGENT"])
        puts "#{id}: #{back ? "back in the working list" : "archived"}"
    end

    # Asking and answering are one task: SET= changes it, and without
    # SET= this says what it is. Reading a state should not mean
    # remembering a second task name.
    desc "Say or set what happened (ID=<report> SET=fixed NOTE=\"…\")"
    task :status do
        store, = deployment
        id, = report_for(store, "data:status")
        want = ENV["SET"]

        if want.nil?
            archived = store.archived?(id) ? ", archived" : ""
            puts "#{id}: #{store.state(id)}#{archived}"
            next
        end

        unless Corrigenda::Store::STATES.include?(want)
            abort "data:status: no such state #{want.inspect} -- " \
                  "#{Corrigenda::Store::STATES.join(", ")}"
        end

        was = store.state(id)
        store.mark(id, want, by: actor, agent: ENV["AGENT"])

        # A reason, if there is one to give. The state change records
        # itself either way; this is the sentence beside it.
        if ENV["NOTE"]
            store.record(id, ENV["NOTE"], by: actor, agent: ENV["AGENT"])
        end

        puts "#{id}: #{was} -> #{want}"
    end

    desc "Remove the reports the config's retention says have expired"
    task :purge do
        store, rules, file = deployment
        next nothing_expires(file) if rules.nil?

        gone = store.purge(rules)
        gone.each { puts report_line(it) }

        # Counted on disk rather than out of the index: a report the
        # index lost is still a directory somebody has to store, and
        # this is the task that says how many there are.
        puts "#{gone.size} removed, #{store.ids.size} left"
    end

    namespace :purge do
        desc "Say what data:purge would remove, and remove nothing"
        task :show do
            store, rules, file = deployment
            next nothing_expires(file) if rules.nil?

            going = store.expired(rules)
            going.each { puts report_line(it) }
            puts "#{going.size} of #{store.ids.size} would go"
        end
    end
end

# rake takes anything that looks like a task name for itself, so flags
# arrive through ARGS:  rake run ARGS="-p 9393 -f"
desc %(Run the service (ARGS="-p 9393 -f" passes flags through))
task run: [:config, MACRO] do
    sh(["./run", *Shellwords.split(ENV.fetch("ARGS", ""))].shelljoin)
end

task default: :test
