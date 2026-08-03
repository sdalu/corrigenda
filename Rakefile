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

    desc "Build the add-on packages (TARGET=firefox builds just one)"
    task :build do
        sh(["extension/build", *ENV["TARGET"]].shelljoin)
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

# rake takes anything that looks like a task name for itself, so flags
# arrive through ARGS:  rake run ARGS="-p 9393 -f"
desc %(Run the service (ARGS="-p 9393 -f" passes flags through))
task run: [:config, MACRO] do
    sh(["./run", *Shellwords.split(ENV.fetch("ARGS", ""))].shelljoin)
end

task default: :test
