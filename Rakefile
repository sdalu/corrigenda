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

# The add-on has a version of its own, and deliberately: it is installed
# rather than served, so a browser may be carrying any of them while the
# service is only ever the one it is running. What it must not have is
# two versions -- the Firefox and Chrome packages are one add-on -- and
# the number is written in each manifest because a manifest has to be
# readable on its own, by a browser and by addons-linter, with nothing
# generated first. So: one command that writes both.
MANIFESTS = FileList["extension/manifest.*.json"]

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
        sh "extension/build"
    end
end

# rake takes anything that looks like a task name for itself, so flags
# arrive through ARGS:  rake run ARGS="-p 9393 -f"
desc %(Run the service (ARGS="-p 9393 -f" passes flags through))
task run: [:config, MACRO] do
    sh(["./run", *Shellwords.split(ENV.fetch("ARGS", ""))].shelljoin)
end

task default: :test
