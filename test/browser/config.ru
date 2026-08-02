# frozen_string_literal: true

require "rack"

$LOAD_PATH.unshift "/web/ops/DebugFeedback/lib"
require "debug_feedback/home"
require "debug_feedback/intake"
require "debug_feedback/prefix"
require "debug_feedback/review"

FIXTURES = File.expand_path("fixtures", __dir__)

use DebugFeedback::Prefix

map("/report") { run DebugFeedback::Intake }
map("/review") { run DebugFeedback::Review }

# The widget is served by the service now, at the path the fixtures ask
# for, so the test loads exactly the file a real page loads instead of a
# copy of it standing in the shared asset tree.
map("/.debug-feedback") { run DebugFeedback::Home }

map("/") { run Rack::Files.new(FIXTURES) }
