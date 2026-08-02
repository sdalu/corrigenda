# frozen_string_literal: true

require_relative "debug_feedback/config"
require_relative "debug_feedback/schema"
require_relative "debug_feedback/store"

# Collects reports about a rendered page: what was picked, what the
# browser looked like, what broke. See DEBUG-FEEDBACK.md for the spec.
module DebugFeedback
    class Error        < StandardError; end
    class PayloadError < Error; end
    class StorageError < Error; end
end
