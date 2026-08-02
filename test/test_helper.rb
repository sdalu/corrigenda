# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

require "json"
require "minitest/autorun"
require "rack/test"
require "stringio"
require "tmpdir"
require "zlib"

require "debug_feedback"
require "debug_feedback/intake"
require "debug_feedback/review"

# One store per process, pointed at a temporary directory. Both apps read
# their config at class level, so the override happens once, here.
module TestSupport
    ROOT = Dir.mktmpdir("feedback-test")

    def self.configure(**overrides)
        config = DebugFeedback::Config.new({ "store" => ROOT }.merge(overrides))
        [DebugFeedback::Intake, DebugFeedback::Review].each do |app|
            app.set(:feedback_config, config)
        end
        config
    end

    def self.document(**overrides)
        {
            "schema" => 1,
            "type"   => "visual",
            "page"   => { "url" => "https://www.alux.fr/", "site" => "www.alux.fr" },
            "message" => "The caption overlaps the photo"
        }.merge(overrides.transform_keys(&:to_s))
    end

    def self.gzip(text)
        io  = StringIO.new(+"", "wb")
        gz  = Zlib::GzipWriter.new(io)
        gz.write(text)
        gz.close
        io.string
    end
end

TestSupport.configure

class FeedbackTest < Minitest::Test
    include Rack::Test::Methods

    def store = @store ||= DebugFeedback::Store.new(TestSupport::ROOT)

    def post_json(document)
        post "/", JSON.generate(document),
             { "CONTENT_TYPE" => "application/json" }
    end
end
