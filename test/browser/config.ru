# frozen_string_literal: true

require "rack"

$LOAD_PATH.unshift "/web/ops/Corrigenda/lib"
require "corrigenda/home"
require "corrigenda/intake"
require "corrigenda/prefix"
require "corrigenda/review"

FIXTURES = File.expand_path("fixtures", __dir__)

use Corrigenda::Prefix

# The service, mounted where a vhost mounts it. The fixtures that set
# data-endpoint by hand keep using the short paths below; the one shaped
# like a MoXoW page advertises /.corrigenda and finds the intake under
# it, which is the arrangement being tested.
map("/.corrigenda/report") { run Corrigenda::Intake }
map("/.corrigenda/review") { run Corrigenda::Review }
map("/.corrigenda")        { run Corrigenda::Home }

map("/report") { run Corrigenda::Intake }
map("/review") { run Corrigenda::Review }

map("/") { run Rack::Files.new(FIXTURES) }
