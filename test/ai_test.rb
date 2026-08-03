# frozen_string_literal: true

require "test_helper"

# The interface a program reads. Most of what is asserted here is what
# it refuses: an endpoint that acts on somebody else's bug list on the
# strength of a request is worth more scepticism than one that renders a
# page.
class AITest < CorrigendaTest
    def app = Corrigenda::AI

    def setup
        @id = store.save(TestSupport.document("message" => "caption overlaps"))
    end

    def teardown
        TestSupport.configure
    end

    def enable(**options)
        TestSupport.configure("ai" => options.empty? ? true : options)
    end

    def body = JSON.parse(last_response.body)

    # Absent from the config is absent from the service: 404, not 403.
    # A route that is switched off should not advertise that it exists.
    def test_it_is_not_there_unless_the_config_says_so
        get "/"
        assert_equal 404, last_response.status

        get "/reports"
        assert_equal 404, last_response.status
    end

    def test_it_describes_itself
        enable
        get "/"

        assert_equal 200, last_response.status
        assert_equal Corrigenda::VERSION, body["version"]
        assert_includes body["routes"].keys, "GET /reports/:id"
        refute body["writable"], "read-only unless the config says otherwise"
    end

    def test_it_lists_reports
        enable
        get "/reports"

        assert_equal 200, last_response.status
        assert_includes body["reports"].map { it["id"] }, @id
    end

    def test_the_listing_can_be_filtered_by_state
        enable
        store.mark(@id, "fixed")

        get "/reports?state=open"
        refute_includes body["reports"].map { it["id"] }, @id

        get "/reports?state=fixed"
        assert_includes body["reports"].map { it["id"] }, @id
    end

    # The archive is somewhere you go on purpose, here as in the UI.
    def test_archived_reports_are_out_of_the_way_but_reachable
        enable
        store.archive(@id)

        get "/reports"
        refute_includes body["reports"].map { it["id"] }, @id

        get "/reports?archived=1"
        assert_includes body["reports"].map { it["id"] }, @id

        get "/reports?archived=all"
        assert_includes body["reports"].map { it["id"] }, @id
    end

    def test_one_report_carries_its_state_and_its_files
        enable
        get "/reports/#{@id}"

        assert_equal 200, last_response.status
        assert_equal "open", body["state"]
        assert_equal false, body["archived"]
        assert_includes body["files"], "report.json"
        assert_equal "caption overlaps", body.dig("report", "message")
    end

    # JSON for the refusals too: a client that has to tell an error from
    # a report by looking at it will get it wrong once.
    def test_an_unknown_report_is_json_as_well
        enable
        get "/reports/20260101T000000Z-deadbeef"

        assert_equal 404, last_response.status
        assert_match(/no such report/, body["error"])
    end

    def test_a_malformed_id_is_refused_rather_than_reaching_the_store
        enable
        get "/reports/nonsense"

        assert_equal 404, last_response.status
        assert_match(/no such report/, body["error"])
    end

    def test_only_the_whitelisted_files_are_served
        enable
        get "/reports/#{@id}/file/state"

        assert_equal 404, last_response.status
        assert_match(/not servable/, body["error"])
    end

    def test_a_screenshot_comes_back_as_an_image
        enable
        id = store.save(TestSupport.document,
                        files: { "screenshot.webp" => "RIFF-ish".b })

        get "/reports/#{id}/file/screenshot.webp"

        assert_equal 200, last_response.status
        assert_equal "image/webp", last_response.content_type
        assert_equal "RIFF-ish", last_response.body
    end

    # Reading is the default; changing what a person filed is not.
    def test_writes_are_refused_unless_the_config_allows_them
        enable
        post "/reports/#{@id}/state", JSON.generate("state" => "fixed"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
        assert_equal "open", store.state(@id)
    end

    def test_a_state_can_be_set_when_writing_is_allowed
        enable("write" => true)
        post "/reports/#{@id}/state", JSON.generate("state" => "fixed"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 200, last_response.status
        assert_equal "fixed", body["state"]
        assert_equal "fixed", store.state(@id)
    end

    def test_an_unknown_state_is_refused_with_the_list_of_real_ones
        enable("write" => true)
        post "/reports/#{@id}/state", JSON.generate("state" => "maybe"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 422, last_response.status
        assert_match(/wontfix/, body["error"])
        assert_equal "open", store.state(@id)
    end

    def test_a_form_post_works_too_since_that_is_what_a_shell_sends
        enable("write" => true)
        post "/reports/#{@id}/state", { "state" => "wontfix" }

        assert_equal 200, last_response.status
        assert_equal "wontfix", store.state(@id)
    end

    def test_archiving_and_bringing_back
        enable("write" => true)
        post "/reports/#{@id}/archive", JSON.generate("archived" => true),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal true, body["archived"]

        post "/reports/#{@id}/archive", JSON.generate("archived" => false),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal false, body["archived"]
    end

    def test_a_configured_token_is_required
        enable("token" => "s3cret")

        get "/reports"
        assert_equal 401, last_response.status

        header "Authorization", "Bearer wrong"
        get "/reports"
        assert_equal 401, last_response.status
    end

    def test_the_right_token_gets_in_either_way_it_is_sent
        enable("token" => "s3cret")

        header "Authorization", "Bearer s3cret"
        get "/reports"
        assert_equal 200, last_response.status

        header "Authorization", nil
        header "X-Corrigenda-Token", "s3cret"
        get "/reports"
        assert_equal 200, last_response.status
    end

    def test_deleting_is_not_offered
        enable("write" => true)
        post "/reports/#{@id}/delete"

        assert_equal 404, last_response.status
        assert_path_exists store.dir_for(@id)
    end
end
