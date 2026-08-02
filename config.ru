# frozen_string_literal: true

require_relative "lib/debug_feedback/intake"
require_relative "lib/debug_feedback/prefix"
require_relative "lib/debug_feedback/review"

NOT_FOUND = lambda do |_env|
    [404, { "content-type" => "text/plain" }, ["not found\n"]]
end

# Before the maps: Rack::URLMap appends its own segment to SCRIPT_NAME,
# so the outer prefix has to be in place first.
use DebugFeedback::Prefix

map("/report") { run DebugFeedback::Intake }
map("/review") { run DebugFeedback::Review }
map("/")       { run NOT_FOUND }
