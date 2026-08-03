# frozen_string_literal: true

require "rack"

$LOAD_PATH.unshift "/web/ops/Corrigenda/lib"
require "corrigenda/home"
require "corrigenda/intake"
require "corrigenda/prefix"
require "corrigenda/review"

FIXTURES = File.expand_path("fixtures", __dir__)

use Corrigenda::Prefix

map("/report") { run Corrigenda::Intake }
map("/review") { run Corrigenda::Review }

# The widget is served by the service now, at the path the fixtures ask
# for, so the test loads exactly the file a real page loads instead of a
# copy of it standing in the shared asset tree.
map("/.corrigenda") { run Corrigenda::Home }

map("/") { run Rack::Files.new(FIXTURES) }
