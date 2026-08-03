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
    # agree with the whitelist rather than describe a wish.
    def test_the_servable_names_are_the_ones_the_schema_offers
        offered = SPEC.dig("paths", "/reports/{id}/file/{name}",
                           "parameters")
                      .find { it["name"] == "name" }
                      .dig("schema", "enum")

        assert_equal Corrigenda::API::SERVABLE.keys.sort, offered.sort
    end

    def test_the_id_pattern_is_the_one_the_app_enforces
        pattern = SPEC.dig("components", "parameters", "ReportId",
                           "schema", "pattern")

        assert_equal Corrigenda::API::ID.source,
                     pattern.sub(/\A\^/, '\A').sub(/\$\z/, '\z')
    end

    # It is served, and it is the file: a client reading the schema from
    # a running service must not be reading a different one.
    def test_the_schema_is_served_as_json
        TestSupport.configure("api" => true)
        get "/openapi.json"

        assert_equal 200, last_response.status
        assert_equal "application/json", last_response.content_type
        assert_equal SPEC, JSON.parse(last_response.body)
    ensure
        TestSupport.configure
    end

    def test_the_schema_is_not_served_when_the_endpoint_is_off
        get "/openapi.json"

        assert_equal 404, last_response.status
    end
end
