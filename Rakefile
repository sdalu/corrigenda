# frozen_string_literal: true

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

# rake takes anything that looks like a task name for itself, so flags
# arrive through ARGS:  rake run ARGS="-p 9393 -f"
desc %(Run the service (ARGS="-p 9393 -f" passes flags through))
task run: [:config, MACRO] do
    sh(["./run", *Shellwords.split(ENV.fetch("ARGS", ""))].shelljoin)
end

task default: :test
