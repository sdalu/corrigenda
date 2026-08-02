# frozen_string_literal: true

require_relative "lib/debug_feedback/intake"
require_relative "lib/debug_feedback/review"

NOT_FOUND = lambda do |_env|
    [404, { "content-type" => "text/plain" }, ["not found\n"]]
end

map("/report") { run DebugFeedback::Intake }
map("/review") { run DebugFeedback::Review }
map("/")       { run NOT_FOUND }
