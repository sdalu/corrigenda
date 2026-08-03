# frozen_string_literal: true

require "test_helper"

# The interface a program reads. Most of what is asserted here is what
# it refuses: an endpoint that acts on somebody else's bug list on the
# strength of a request is worth more scepticism than one that renders a
# page.
class APITest < CorrigendaTest
    def app = Corrigenda::API

    def setup
        @id = store.save(TestSupport.document("message" => "caption overlaps"))
    end

    def teardown
        TestSupport.configure
    end

    def enable(**options)
        TestSupport.configure("api" => options.empty? ? true : options)
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

    # A filter applied inside the limit would answer "the fixed ones"
    # with whichever of the newest hundred happened to be fixed, and a
    # client cannot tell that from "there are none".
    def test_a_filter_looks_past_the_limit_it_was_given
        enable
        store.mark(@id, "wontfix")
        20.times { store.save(TestSupport.document) }

        get "/reports?state=wontfix&limit=1"

        assert_includes body["reports"].map { it["id"] }, @id
    end

    # Two numbers, because one of them is a decision: how many answered
    # the filter, and how many came back.
    def test_the_listing_says_how_many_it_did_not_send
        enable
        3.times { store.save(TestSupport.document) }

        get "/reports?limit=2"

        assert_equal 2, body["count"]
        assert_equal 2, body["reports"].size
        assert_operator body["matched"], :>, 2
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

    # One resource, one representation: a client that wants to change
    # both things should not make two requests and hope.
    def test_patch_sets_a_state_and_the_archive_marker_at_once
        enable("write" => true)
        patch "/reports/#{@id}",
              JSON.generate("state" => "fixed", "archived" => true),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 200, last_response.status
        assert_equal "fixed", body["state"]
        assert_equal true, body["archived"]
        assert_equal "fixed", store.state(@id)
        assert store.archived?(@id)
    end

    def test_patch_is_refused_on_a_read_only_deployment
        enable
        patch "/reports/#{@id}", JSON.generate("state" => "fixed"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
        assert_equal "open", store.state(@id)
    end

    # A field a report cannot be told is a client's misunderstanding,
    # and silence would let it believe the change happened.
    def test_patch_refuses_a_field_that_is_not_a_report_s_to_change
        enable("write" => true)
        patch "/reports/#{@id}", JSON.generate("summary" => "nicer words"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 422, last_response.status
        assert_match(/summary/, body["error"])
    end

    def test_patch_refuses_a_state_that_is_not_one
        enable("write" => true)
        patch "/reports/#{@id}", JSON.generate("state" => "maybe"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 422, last_response.status
        assert_equal "open", store.state(@id)
    end

    # For anything that polls: the report itself never changes, so only
    # the markers beside it can, and the ETag is those.
    def test_a_report_answers_304_when_nothing_about_it_changed
        enable
        get "/reports/#{@id}"
        tag = last_response.headers["ETag"]

        refute_nil tag
        header "If-None-Match", tag
        get "/reports/#{@id}"

        assert_equal 304, last_response.status
        assert_empty last_response.body
    end

    def test_the_tag_changes_when_the_state_does
        enable
        get "/reports/#{@id}"
        was = last_response.headers["ETag"]

        store.mark(@id, "fixed")
        header "If-None-Match", was
        get "/reports/#{@id}"

        assert_equal 200, last_response.status
        refute_equal was, last_response.headers["ETag"]
    end

    def test_a_file_is_not_sent_twice
        enable
        id = store.save(TestSupport.document,
                        files: { "screenshot.webp" => "RIFF-ish".b })

        get "/reports/#{id}/file/screenshot.webp"
        tag = last_response.headers["ETag"]

        assert_equal 200, last_response.status
        header "If-None-Match", tag
        get "/reports/#{id}/file/screenshot.webp"

        assert_equal 304, last_response.status
    end

    # A client that tried DELETE guessed something reasonable and is
    # owed the reason, with the header a program reads.
    def test_delete_says_405_and_what_is_allowed
        enable("write" => true)
        delete "/reports/#{@id}"

        assert_equal 405, last_response.status
        assert_equal "GET, PATCH", last_response.headers["Allow"]
        assert_match(/review UI/, body["error"])
        assert_path_exists store.dir_for(@id)
    end

    # The trail. What an agent did about a report is the thing a person
    # will want to check afterwards, so it is recorded rather than
    # implied by a state that changed at some point.
    def test_a_note_can_be_recorded_and_read_back
        enable("write" => true)
        post "/reports/#{@id}/journal",
             JSON.generate("note" => "raised the contrast to 4.8:1",
                           "agent" => "claude", "refs" => ["abc1234"]),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 201, last_response.status
        assert_equal "note", body["kind"]
        assert_equal "claude", body["agent"]

        get "/reports/#{@id}/journal"

        assert_equal 1, body["count"]
        assert_equal "raised the contrast to 4.8:1",
                     body["entries"].first["note"]
    end

    def test_the_journal_comes_with_the_report
        enable("write" => true)
        store.record(@id, "looked at it")

        get "/reports/#{@id}"

        assert_equal ["looked at it"], body["journal"].map { it["note"] }
    end

    # The server's clock and the server's idea of who is calling: a
    # client cannot backdate an entry or sign it as somebody else.
    def test_a_client_cannot_write_the_time_or_the_actor
        enable("write" => true)
        header "X-Remote-User", "sdalu"
        post "/reports/#{@id}/journal",
             JSON.generate("note" => "did a thing",
                           "at" => "1999-01-01T00:00:00Z", "by" => "root"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 201, last_response.status
        assert_equal "sdalu", body["by"]
        refute_equal "1999-01-01T00:00:00Z", body["at"]
    end

    def test_an_empty_note_is_refused
        enable("write" => true)
        post "/reports/#{@id}/journal", JSON.generate("note" => "  "),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 422, last_response.status
    end

    def test_recording_needs_write_access
        enable
        post "/reports/#{@id}/journal", JSON.generate("note" => "hello"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
        assert_empty store.journal(@id)
    end

    # A change and the reason for it in one request: asking for a second
    # call is how a trail ends up with states nobody explained.
    def test_a_patch_can_carry_the_reason_with_the_change
        enable("write" => true)
        patch "/reports/#{@id}",
              JSON.generate("state" => "fixed", "agent" => "claude",
                            "note" => "padding was 2px, now 8px"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 200, last_response.status
        kinds = body["journal"].map { it["kind"] }

        assert_equal %w[state note], kinds
        assert_equal "claude", body["journal"].first["agent"]
    end

    def test_the_tag_changes_when_something_is_recorded
        enable("write" => true)
        get "/reports/#{@id}"
        was = last_response.headers["ETag"]

        store.record(@id, "an entry")
        header "If-None-Match", was
        get "/reports/#{@id}"

        assert_equal 200, last_response.status
    end

    # The distinction this exists for: a caller may be trusted to say
    # what it tried without being trusted to declare something fixed.
    def test_a_recorder_may_write_in_the_journal_and_nothing_else
        enable("record" => true)

        post "/reports/#{@id}/journal",
             JSON.generate("note" => "reproduced at 380px", "agent" => "claude"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 201, last_response.status
        assert_equal 1, store.journal(@id).size

        post "/reports/#{@id}/state", JSON.generate("state" => "fixed"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
        assert_equal "open", store.state(@id)
    end

    # A PATCH is answered by what its body carries, not by its verb: one
    # that only says what was tried needs the permission to say things.
    def test_a_recorder_may_patch_a_note_but_not_a_state
        enable("record" => true)

        patch "/reports/#{@id}", JSON.generate("note" => "looked, no change"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 200, last_response.status
        assert_equal ["looked, no change"], body["journal"].map { it["note"] }

        patch "/reports/#{@id}", JSON.generate("state" => "fixed"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
    end

    # And the other way: a deployment can let a program move a report
    # without letting it write prose into somebody's record.
    def test_a_writer_can_be_refused_the_journal
        enable("write" => true, "record" => false)

        patch "/reports/#{@id}", JSON.generate("state" => "fixed"),
              { "CONTENT_TYPE" => "application/json" }

        assert_equal 200, last_response.status
        assert_equal "fixed", store.state(@id)

        # The state change still recorded itself: that line is the
        # service's, not the caller's.
        assert_equal ["state"], store.journal(@id).map { it["kind"] }

        post "/reports/#{@id}/journal", JSON.generate("note" => "and also"),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 403, last_response.status
    end

    def test_the_capability_document_answers_both_questions
        enable("record" => true)
        get "/"

        refute body["writable"]
        assert body["recordable"]
    end

    def test_deleting_is_not_offered
        enable("write" => true)
        post "/reports/#{@id}/delete"

        assert_equal 404, last_response.status
        assert_path_exists store.dir_for(@id)
    end
end
