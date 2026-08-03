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

    # Nothing expires unless a deployment says so, and what it says is
    # refused rather than interpreted: every wrong reading of this key
    # deletes somebody's bug list.
    def test_no_retention_is_the_default
        assert_nil Corrigenda::Config.new.retention
    end

    def test_retention_is_read_as_whole_days_per_rule
        File.write(@file, "retention:\n  archived: 90\n  any: 365\n")

        assert_equal({ "archived" => 90, "any" => 365 },
                     Corrigenda::Config.load(@file).retention)
    end

    def test_one_rule_alone_is_a_rule
        File.write(@file, "retention:\n  archived: 30\n")

        assert_equal({ "archived" => 30 },
                     Corrigenda::Config.load(@file).retention)
    end

    # A key written but left blank is an edit in progress, not a policy.
    def test_a_blank_rule_is_not_a_rule
        File.write(@file, "retention:\n  archived:\n")

        assert_nil Corrigenda::Config.load(@file).retention
    end

    def test_an_unknown_rule_is_refused
        File.write(@file, "retention:\n  yesterday: 5\n")

        error = assert_raises(ArgumentError) {
            Corrigenda::Config.load(@file).retention
        }
        assert_match(/yesterday/, error.message)
    end

    def test_days_that_are_not_days_are_refused
        %w[soon 0 -5].each do |value|
            File.write(@file, "retention:\n  any: #{value}\n")

            assert_raises(ArgumentError,
                          "#{value} should not be days") {
                Corrigenda::Config.load(@file).retention
            }
        end
    end

    # The interface is absent unless asked for, and what it may do is a
    # list rather than a row of switches: `write: [journal, state]`
    # reads as the sentence it is.
    def test_there_is_no_agent_interface_by_default
        assert_nil Corrigenda::Config.new.api
    end

    def test_true_is_a_read_only_interface
        File.write(@file, "api: true\n")
        api = Corrigenda::Config.load(@file).api

        assert_empty api["allows"]
        assert_nil api["token"]
    end

    def test_false_is_the_same_as_absent
        File.write(@file, "api: false\n")

        assert_nil Corrigenda::Config.load(@file).api
    end

    def test_write_lists_what_may_be_done
        File.write(@file, "api:\n  write: [journal, state]\n")

        assert_equal %w[journal state],
                     Corrigenda::Config.load(@file).api["allows"]
    end

    # Kept in the order the grants are defined in, whatever order the
    # config wrote them: this is displayed, and a list that reshuffles
    # itself reads as a change.
    def test_the_grants_come_back_in_a_stable_order
        File.write(@file, "api:\n  write: [state, journal, archive]\n")

        assert_equal %w[journal archive state],
                     Corrigenda::Config.load(@file).api["allows"]
    end

    def test_write_true_is_all_of_them
        File.write(@file, "api:\n  write: true\n")

        assert_equal Corrigenda::Config::API_GRANTS,
                     Corrigenda::Config.load(@file).api["allows"]
    end

    def test_a_single_grant_need_not_be_a_list
        File.write(@file, "api:\n  write: journal\n")

        assert_equal ["journal"], Corrigenda::Config.load(@file).api["allows"]
    end

    def test_a_grant_nobody_defines_is_refused
        File.write(@file, "api:\n  write: [journal, delete]\n")

        error = assert_raises(ArgumentError) {
            Corrigenda::Config.load(@file).api
        }
        assert_match(/delete/, error.message)
    end

    def test_a_token_is_read_as_written
        File.write(@file, "api:\n  token: s3cret\n  write: [archive]\n")
        api = Corrigenda::Config.load(@file).api

        assert_equal "s3cret", api["token"]
        assert_equal ["archive"], api["allows"]
    end

    def test_an_unknown_setting_is_refused
        File.write(@file, "api:\n  delete: true\n")

        error = assert_raises(ArgumentError) {
            Corrigenda::Config.load(@file).api
        }
        assert_match(/delete/, error.message)
    end

    # Somebody meant to paste a secret and did not. Reading that as "no
    # token wanted" would open the endpoint at the moment they were
    # trying to close it.
    def test_an_empty_token_is_refused
        File.write(@file, %(api:\n  token: ""\n))

        assert_raises(ArgumentError) { Corrigenda::Config.load(@file).api }
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
