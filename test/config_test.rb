# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
    def setup
        @file = File.join(Dir.mktmpdir("config-test"), "local.yml")
        File.write(@file, "store: /from/the/file\nmax_report: 99\n")
    end

    def teardown
        ENV.delete("DEBUG_FEEDBACK_STORE")
        ENV.delete("DEBUG_FEEDBACK_SITES")
    end

    def test_an_absent_file_is_a_valid_config
        assert_equal Pathname("store"),
                     DebugFeedback::Config.load("/nowhere/at/all").store_path
    end

    def test_the_file_is_read
        config = DebugFeedback::Config.load(@file)

        assert_equal Pathname("/from/the/file"), config.store_path
        assert_equal 99, config.max_report
    end

    # So one config can be pointed at another store without a second copy
    # of it being written somewhere.
    def test_the_environment_overrides_the_store_and_nothing_else
        ENV["DEBUG_FEEDBACK_STORE"] = "/from/the/env"
        config = DebugFeedback::Config.load(@file)

        assert_equal Pathname("/from/the/env"), config.store_path
        assert_equal 99, config.max_report
    end

    def test_the_environment_can_replace_the_allowlist
        File.write(@file, "sites:\n  - a.test\n")
        ENV["DEBUG_FEEDBACK_SITES"] = "b.test, c.test"
        config = DebugFeedback::Config.load(@file)

        assert config.site_allowed?("b.test")
        refute config.site_allowed?("a.test")
    end

    # Empty is not the same as unset: it means drop the list entirely,
    # which is what a local run needs against a production config.
    def test_an_empty_environment_list_accepts_any_site
        File.write(@file, "sites:\n  - a.test\n")
        ENV["DEBUG_FEEDBACK_SITES"] = ""

        assert DebugFeedback::Config.load(@file).site_allowed?("anything.test")
    end

    def test_a_site_list_is_what_makes_a_site_refusable
        assert DebugFeedback::Config.new.site_allowed?("anything.test")
        refute DebugFeedback::Config.new("sites" => ["a.test"])
                                    .site_allowed?("b.test")
    end
end
