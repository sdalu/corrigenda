# frozen_string_literal: true

require "rack"

$LOAD_PATH.unshift "/web/ops/DebugFeedback/lib"
require "debug_feedback/intake"
require "debug_feedback/prefix"
require "debug_feedback/review"

FIXTURES = File.expand_path("fixtures", __dir__)

use DebugFeedback::Prefix

map("/report")    { run DebugFeedback::Intake }
map("/review")    { run DebugFeedback::Review }
map("/common/js") { run Rack::Files.new("/web/platform/Common/js") }
map("/")          { run Rack::Files.new(FIXTURES) }
