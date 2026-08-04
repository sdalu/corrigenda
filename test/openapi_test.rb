# frozen_string_literal: true

require "test_helper"

# A description that has drifted from the thing it describes is worse
# than none: it is believed. So the schema is not generated from the
# routes -- that would only restate them -- and it is not left to
# goodwill either. These assertions fail on either side moving.
class OpenapiTest < CorrigendaTest
    def app = Corrigenda::API

    SPEC = Corrigenda::API.openapi

    # "/reports/:id/file/:name" the way OpenAPI spells it.
    def self.as_openapi(pattern)
        path = pattern.to_s.gsub(/:(\w+)/) { "{#{Regexp.last_match(1)}}" }
        path.empty? ? "/" : path
    end

    def routes
        Corrigenda::API.routes.flat_map { |verb, defined|
            defined.map { [verb.downcase, self.class.as_openapi(it[0])] }
        }.reject { |verb, _| verb == "head" }.to_set
    end

    def documented
        SPEC.fetch("paths").flat_map { |path, operations|
            operations.keys
                      .select { %w[get post patch put delete].include?(it) }
                      .map { [it, path] }
        }.to_set
    end

    def test_every_route_is_in_the_schema
        assert_empty (routes - documented).to_a,
                     "routes the schema does not describe"
    end

    def test_the_schema_describes_nothing_that_is_not_there
        assert_empty (documented - routes).to_a,
                     "schema entries with no route behind them"
    end

    # The service's own version, not a number somebody remembered to
    # bump: a schema that says 0.1.0 against a 0.4 service is a schema
    # nobody can date.
    def test_the_schema_says_the_version_the_service_is
        assert_equal Corrigenda::VERSION, SPEC.dig("info", "version")
    end

    def test_the_states_in_the_schema_are_the_states_of_the_store
        assert_equal Corrigenda::Store::STATES,
                     SPEC.dig("components", "schemas", "State", "enum")
    end

    # The one place a file name is a path component, so the schema must
    # agree with the whitelist rather than describe a wish. It is a
    # pattern rather than a list now, because a journal line can carry
    # a picture and those are numbered as they arrive.
    def test_the_servable_names_are_the_ones_the_schema_offers
        offered = SPEC.dig("paths", "/reports/{id}/file/{name}",
                           "parameters")
                      .find { it["name"] == "name" }
                      .dig("schema", "pattern")
        allowed = Regexp.new(offered)

        Corrigenda::Store::SERVABLE.each_key { assert_match allowed, it }
        assert_match allowed, "shot-1.webp"
        assert_match allowed, "shot-12.png"
        refute_match allowed, "journal.jsonl"
        refute_match allowed, "state"
    end

    # And the store is what names those pictures, so the pattern has
    # to agree with it rather than with a hope about it.
    def test_every_name_the_schema_allows_is_one_the_store_serves
        offered = SPEC.dig("paths", "/reports/{id}/file/{name}",
                           "parameters")
                      .find { it["name"] == "name" }
                      .dig("schema", "pattern")

        %w[shot-1.webp shot-2.png shot-3.jpg].each do |name|
            assert_match Regexp.new(offered), name
            refute_nil Corrigenda::Store.shot_type(name)
        end
    end

    def test_the_id_pattern_is_the_one_the_app_enforces
        pattern = SPEC.dig("components", "parameters", "ReportId",
                           "schema", "pattern")

        assert_equal Corrigenda::Store::ID.source,
                     pattern.sub(/\A\^/, '\A').sub(/\$\z/, '\z')
    end

    # The schema is read by agents as well as by client generators, and
    # the advice is per operation because that is where it is needed:
    # what this route is good for, and the mistake it invites. A new
    # route without one is the failure this catches.
    def operations
        SPEC.fetch("paths").flat_map { |path, verbs|
            verbs.filter_map { |verb, operation|
                next unless %w[get post patch put delete].include?(verb)

                ["#{verb.upcase} #{path}", operation]
            }
        }
    end

    def test_every_operation_says_something_to_an_agent
        without = operations.reject { |_, operation|
            operation["description"].to_s.include?("🤖 **For AI:**")
        }.map(&:first)

        assert_empty without, "operations with no 🤖 For AI section"
    end

    # Above the rule: what the route is. Below it: what to do about it.
    # A rule with nothing above separates nothing.
    def test_the_agent_section_comes_after_a_rule_and_some_prose
        operations.each do |name, operation|
            description = operation["description"].to_s

            # The rule is written as markdown rather than as an `<hr>`
            # tag: a raw HTML block stops the renderer parsing markdown
            # for the rest of the description, and everything after it —
            # the emphasis, the `code spans` — came out as literal
            # asterisks and backticks in the viewer.
            assert_includes description, "\n---", "#{name} has no rule"
            above = description.split("\n---").first.to_s.strip
            refute_empty above, "#{name} opens with the rule"
        end
    end

    # GET /api/ is the orientation a client that knows nothing reads
    # first, so an operation it does not mention is one agents never
    # find -- which is exactly what happened to the journal write: it
    # existed, the schema described it, and the route list at the door
    # said nothing. Held to the schema so it cannot happen twice.
    def test_the_orientation_names_every_operation
        TestSupport.configure("api" => true)
        get "/"

        named = JSON.parse(last_response.body).fetch("routes").keys
                    .map { it.split(" ", 2) }
                    .map { |verb, path|
                        [verb.downcase, self.class.as_openapi(path)]
                    }.to_set

        expected = documented.reject { |_, path| path == "/" }.to_set

        assert_empty (expected - named).to_a,
                     "operations GET / does not mention"
        assert_empty (named - expected).to_a,
                     "routes GET / invents"
    ensure
        TestSupport.configure
    end

    # It is served, and it is the file -- except `servers`, which the
    # route rewrites to the mount the request came through, because Try
    # it out sends requests wherever it points. Everything else must
    # still be the file, byte for byte: a served copy that drifted
    # further than that would be a second description.
    def test_the_schema_is_served_as_json_with_its_own_mount
        TestSupport.configure("api" => true)
        get "/openapi.json"

        assert_equal 200, last_response.status
        assert_equal "application/json", last_response.content_type

        served = JSON.parse(last_response.body)

        assert_equal SPEC.except("servers"), served.except("servers")
        # Unmounted (this test hits the app bare), the file's own
        # default is the only honest answer.
        assert_equal "/api", served.dig("servers", 0, "url")
    ensure
        TestSupport.configure
    end

    def test_the_schema_is_not_served_when_the_endpoint_is_off
        get "/openapi.json"

        assert_equal 404, last_response.status
    end
end
