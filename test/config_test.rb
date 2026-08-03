# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
    def setup
        @file = File.join(Dir.mktmpdir("config-test"), "local.yml")
        File.write(@file, "store: /from/the/file\nmax_report: 99\n")
    end

    def teardown
        ENV.delete("CORRIGENDA_STORE")
        ENV.delete("CORRIGENDA_SITES")
    end

    def test_an_absent_file_is_a_valid_config
        assert_equal Pathname("store"),
                     Corrigenda::Config.load("/nowhere/at/all").store_path
    end

    def test_the_file_is_read
        config = Corrigenda::Config.load(@file)

        assert_equal Pathname("/from/the/file"), config.store_path
        assert_equal 99, config.max_report
    end

    # So one config can be pointed at another store without a second copy
    # of it being written somewhere.
    def test_the_environment_overrides_the_store_and_nothing_else
        ENV["CORRIGENDA_STORE"] = "/from/the/env"
        config = Corrigenda::Config.load(@file)

        assert_equal Pathname("/from/the/env"), config.store_path
        assert_equal 99, config.max_report
    end

    def test_the_environment_can_replace_the_allowlist
        File.write(@file, "sites:\n  - a.test\n")
        ENV["CORRIGENDA_SITES"] = "b.test, c.test"
        config = Corrigenda::Config.load(@file)

        assert config.site_allowed?("b.test")
        refute config.site_allowed?("a.test")
    end

    # Empty is not the same as unset: it means drop the list entirely,
    # which is what a local run needs against a production config.
    def test_an_empty_environment_list_accepts_any_site
        File.write(@file, "sites:\n  - a.test\n")
        ENV["CORRIGENDA_SITES"] = ""

        assert Corrigenda::Config.load(@file).site_allowed?("anything.test")
    end

    def test_a_site_list_is_what_makes_a_site_refusable
        assert Corrigenda::Config.new.site_allowed?("anything.test")
        refute Corrigenda::Config.new("sites" => ["a.test"])
                                    .site_allowed?("b.test")
    end

    # The origins that may post from elsewhere are the sites that may be
    # reported on: one list, so there is nothing to fall out of step.
    def test_an_origin_is_allowed_when_its_site_is
        config = Corrigenda::Config.new("sites" => ["a.test"])

        assert config.origin_allowed?("https://a.test")
        refute config.origin_allowed?("https://b.test")
    end

    def test_only_https_origins_are_allowed
        config = Corrigenda::Config.new("sites" => ["a.test"])

        refute config.origin_allowed?("http://a.test")
        refute config.origin_allowed?("a.test")
    end

    # Loopback has no certificate to have, and a browser test must be
    # able to prove the cross-origin path without inventing one.
    def test_http_is_allowed_from_loopback_only
        config = Corrigenda::Config.new

        assert config.origin_allowed?("http://localhost:9397")
        assert config.origin_allowed?("http://127.0.0.1:9393")
        refute config.origin_allowed?("http://not-localhost.test")
    end

    def test_a_missing_origin_is_not_an_allowed_one
        config = Corrigenda::Config.new

        refute config.origin_allowed?(nil)
        refute config.origin_allowed?("")
    end

    # No allowlist means development, where any site is accepted and any
    # https origin with it — the two answers stay the same answer.
    def test_no_allowlist_allows_any_https_origin
        config = Corrigenda::Config.new

        assert config.origin_allowed?("https://anything.test")
        refute config.origin_allowed?("http://anything.test")
    end
end
