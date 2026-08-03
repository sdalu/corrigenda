# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

require "json"
require "minitest/autorun"
require "rack/test"
require "stringio"
require "tmpdir"
require "zlib"

require "corrigenda"
require "corrigenda/home"
require "corrigenda/intake"
require "corrigenda/prefix"
require "corrigenda/review"

# Untracked, and usually absent: the place for anything a test needs
# that names a deployment rather than the program. Everything here
# runs on example.com, so a checkout needs no such file -- but when
# a real host is genuinely required, it goes in one file that is not
# committed rather than scattered through the suites.
LOCAL = File.expand_path("local.rb", __dir__)
require_relative "local" if File.exist?(LOCAL)

# One store per process, pointed at a temporary directory. Both apps read
# their config at class level, so the override happens once, here.
module TestSupport
    ROOT = Dir.mktmpdir("corrigenda-test")

    def self.configure(**overrides)
        config = Corrigenda::Config.new({ "store" => ROOT }.merge(overrides))
        [Corrigenda::Home, Corrigenda::Intake, Corrigenda::Review].each do |app|
            app.set(:feedback_config, config)
        end
        config
    end

    def self.document(**overrides)
        {
            "schema" => 1,
            "type"   => "visual",
            "page"   => { "url" => "https://www.example.com/", "site" => "www.example.com" },
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

class CorrigendaTest < Minitest::Test
    include Rack::Test::Methods

    def store = @store ||= Corrigenda::Store.new(TestSupport::ROOT)

    def post_json(document)
        post "/", JSON.generate(document),
             { "CONTENT_TYPE" => "application/json" }
    end
end
