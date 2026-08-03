# frozen_string_literal: true

require "test_helper"

class ReviewTest < CorrigendaTest
    def app = Corrigenda::Review

    # Every id the index still carries, archived or not.
    def listed = store.entries(archived: nil, limit: 1000)
                      .map { it.fetch("id") }

    def setup
        TestSupport.configure
        @id = store.save(
            TestSupport.document(
                "target" => {
                    "selector" => "#gallery .caption",
                    "html"     => "<p>caption</p>",
                    "rules" => [
                        { "href" => "/common/style/exhibition-standard.css",
                          "selector" => ".caption",
                          "context" => "@layer components / @media (width > 20rem)" }
                    ]
                },
                "environment" => { "viewport" => "390x844" }
            ),
            files: { "screenshot.webp" => "RIFF....WEBP".b },
            reporter: "alice"
        )
    end

    def test_the_listing_shows_a_report
        get "/"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "www.example.com"
    end

    def test_the_listing_is_reachable_under_a_vhost_host_header
        get "/", {}, { "HTTP_HOST" => "tools.example.com" }

        assert_predicate last_response, :ok?
    end

    def test_the_detail_names_the_stylesheet_that_matched
        get "/#{@id}"

        assert_includes last_response.body, "exhibition-standard.css"
        assert_includes last_response.body, "#gallery .caption"
    end

    # The cascade context is the point of the field: which layer and
    # which media query had to hold for the rule to apply. It opens from
    # the selector now — a report on a heavily styled element carries a
    # dozen rules, and a dozen four-line blocks is a wall — so the
    # selector is in the summary and the strata are what unfolds.
    def test_the_detail_shows_the_cascade_context
        get "/#{@id}"

        # Each band says which of the three kinds it is, so the edge can
        # be coloured by what it answers: which layer, under what
        # condition, inside what.
        assert_includes last_response.body,
                        %(<li class="is-layer">@layer components</li>)
        assert_includes last_response.body,
                        %(<li class="is-condition">@media (width &gt; 20rem)</li>)
        assert_includes last_response.body, %(<span class="selector">.caption)
        assert_includes last_response.body, "2 deep"
    end

    def test_a_nested_selector_band_is_marked_as_nesting
        id = store.save(TestSupport.document(
            "target" => { "selector" => "li",
                          "rules" => [{ "selector" => "& li",
                                        "context" => "@layer base / .crumbs",
                                        "href" => "/style/main.css" }] }))

        get "/#{id}"

        assert_includes last_response.body, %(<li class="is-nesting">.crumbs</li>)
    end

    # A rule that matched with no layer and no query has nothing to
    # unfold, and is not dressed as though it had.
    def test_a_rule_without_context_is_not_a_disclosure
        id = store.save(TestSupport.document(
            "target" => { "selector" => "p",
                          "rules" => [{ "selector" => ".plain", "context" => "",
                                        "href" => "/style/main.css" }] }))

        get "/#{id}"

        assert_includes last_response.body, %(<p class="rule is-bare">)
        refute_includes last_response.body, %(<details class="rule">\n                <summary>\n                    <span class="selector">.plain)
    end

    # The review UI renders strings a browser sent us. escape_html only
    # works if Tilt picked Erubi, so assert the outcome, not the setting.
    def test_reported_text_is_escaped_not_executed
        id = store.save(TestSupport.document(
                            "message" => "<script>alert(1)</script>"))

        get "/#{id}"

        refute_includes last_response.body, "<script>alert(1)</script>"
        assert_includes last_response.body, "&lt;script&gt;"
    end

def test_the_listing_marks_which_channels_were_sent
    store.save(TestSupport.document(
                   "capture" => { "fragment" => true, "rules" => true,
                                  "computed" => false }))
    get "/"

    # The letter stands for the word the legend prints, not for the
    # payload key: "fragment" is the element you picked.
    assert_includes last_response.body,
                    %(<span class="chip" data-channel="fragment" title="element">E</span>)
    assert_includes last_response.body,
                    %(<span class="chip" data-channel="rules" title="css rules">R</span>)
    # The legend prints a chip for every channel, so absence has to
    # be asserted on a ROW chip -- those carry the title.
    refute_includes last_response.body,
                    %(data-channel="computed" title=)
end

    def test_an_unknown_report_is_a_404
        get "/20260101T000000Z-deadbeef"

        assert_equal 404, last_response.status
    end

    def test_the_screenshot_is_served
        get "/#{@id}/file/screenshot.webp"

        assert_predicate last_response, :ok?
        assert_equal "image/webp", last_response.content_type
    end

    # The name is a path component, so only known ones are served.
    def test_arbitrary_files_are_not_served
        get "/#{@id}/file/state"

        assert_equal 404, last_response.status
    end

    def test_state_can_be_changed_and_shows_in_the_listing
        post "/#{@id}/state", { "state" => "fixed" }

        assert_equal 302, last_response.status
        assert_equal "fixed", store.state(@id)
    end

    # Triaging a morning's reports meant opening each one and coming
    # back. The listing sets a state from the row, and lands you back on
    # the list you were reading rather than inside the report.
    def test_the_listing_offers_every_state_on_each_row
        get "/"

        assert_includes last_response.body, %(name="state" value="fixed")
        assert_match %r{name="from"\s+value="list"}, last_response.body
    end

    def test_a_state_set_from_the_listing_returns_to_the_listing
        post "/#{@id}/state", { "state" => "fixed", "from" => "list" }

        assert_equal 302, last_response.status
        assert_equal "fixed", store.state(@id)
        assert_match %r{/\z}, last_response.headers["location"]
    end

    def test_it_returns_to_the_archive_when_that_is_where_you_were
        store.archive(@id)
        post "/#{@id}/state", { "state" => "wontfix", "from" => "archive" }

        assert_equal "/?archived=1", last_response.headers["location"]
    end

    # The other half of triage, and it used to mean opening the report:
    # the state says what happened to the defect, this says whether
    # anybody still wants it in front of them.
    def test_a_report_is_filed_from_its_row
        get "/"

        assert_match %r{name="archived"\s+value="1"}, last_response.body

        post "/#{@id}/archive", { "archived" => "1", "from" => "list" }

        assert store.archived?(@id)
        assert_equal "/", last_response.headers["location"]
    end

    # `archived` says what to do, not where the press came from. Read as
    # the way back it sent whoever archived something from the working
    # list into the archive to watch it arrive.
    def test_filing_from_the_working_list_stays_on_the_working_list
        post "/#{@id}/archive", { "archived" => "1", "from" => "list" }

        assert_equal "/", last_response.headers["location"]
    end

    def test_filing_from_a_report_stays_on_the_report
        post "/#{@id}/archive", { "archived" => "1" }

        assert_equal "/#{@id}", last_response.headers["location"]
    end

    # From a report's own page, nothing changes: you stay on the report.
    def test_a_state_set_from_a_report_stays_on_the_report
        post "/#{@id}/state", { "state" => "fixed" }

        assert_equal "/#{@id}", last_response.headers["location"]
    end

    def test_an_unknown_state_is_refused
        post "/#{@id}/state", { "state" => "maybe" }

        assert_equal 400, last_response.status
    end

    # A fragment carries the reported page's relative URLs. Displayed
    # here they used to resolve against this app: an <img src="photo.jpg">
    # in a captured card asked for a report named photo.jpg, the store
    # refused an id it could not parse, and the reporter got a 500.
    def test_a_name_that_cannot_be_an_id_is_not_found
        get "/photo.jpg"

        assert_equal 404, last_response.status
    end

    def test_a_file_under_a_name_that_cannot_be_an_id_is_not_found
        get "/photo.jpg/file/screenshot.webp"

        assert_equal 404, last_response.status
    end

    # And the reason those requests stop arriving: the frame is told
    # where its contents came from.
    def test_the_fragment_resolves_against_the_page_it_came_from
        store.save(TestSupport.document(
            "target" => { "selector" => "figure", "html" => "<img src='photo.jpg'>" }))
        id = store.entries(limit: 1).first.fetch("id")

        get "/#{id}"

        assert_includes last_response.body,
                        "&lt;base href=&quot;https://www.example.com/&quot;&gt;"
    end

    # ----------------------------------------------------------------
    # Archiving: out of the list, still on disk. Two questions, two
    # files -- a report is archived AND fixed, or archived and wontfix.
    # ----------------------------------------------------------------
    def test_archiving_takes_a_report_out_of_the_working_list
        post "/#{@id}/archive", { "archived" => "1" }

        assert_equal 302, last_response.status

        get "/"

        refute_includes last_response.body, @id
    end

    def test_an_archived_report_is_in_the_archive
        post "/#{@id}/archive", { "archived" => "1" }

        get "/?archived=1"

        assert_includes last_response.body, @id
    end

    def test_archiving_keeps_the_state_it_had
        post "/#{@id}/state", { "state" => "fixed" }
        post "/#{@id}/archive", { "archived" => "1" }

        assert_equal "fixed", store.state(@id)
        assert store.archived?(@id)
    end

    def test_unarchiving_brings_it_back
        post "/#{@id}/archive", { "archived" => "1" }
        post "/#{@id}/archive", { "archived" => "0" }

        refute store.archived?(@id)

        get "/"

        assert_includes last_response.body, @id
    end

    # A switch, so the word beside it stays put and the control says
    # which way it is: what it posts is the opposite of what it shows.
    def test_the_archive_switch_shows_where_it_stands
        get "/#{@id}"

        assert_match %r{role="switch"\s+aria-checked="false"}, last_response.body
        assert_match %r{name="archived" value="1"}, last_response.body

        post "/#{@id}/archive", { "archived" => "1" }
        get "/#{@id}"

        assert_match %r{aria-checked="true"}, last_response.body
        assert_match %r{name="archived" value="0"}, last_response.body
    end

    def test_archiving_something_that_is_not_there_is_not_found
        post "/20260101T000000Z-deadbeef/archive", { "archived" => "1" }

        assert_equal 404, last_response.status
    end

    # ----------------------------------------------------------------
    # Deleting: gone. Asked twice, because there is no undo.
    # ----------------------------------------------------------------
    def test_the_first_delete_asks_rather_than_deletes
        post "/#{@id}/delete"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "Delete this report?"
        assert_path_exists store.dir_for(@id).to_s
    end

    # The usual reason for arriving on that page is wanting the report
    # out of the list, which archiving does without destroying it.
    def test_the_confirmation_offers_archiving_instead
        post "/#{@id}/delete"

        assert_includes last_response.body, "Archive instead"
        assert_includes last_response.body, "/#{@id}/archive"
    end

    def test_an_archived_report_is_not_offered_archiving_again
        post "/#{@id}/archive", { "archived" => "1" }
        post "/#{@id}/delete"

        refute_includes last_response.body, "Archive instead"
    end

    def test_a_confirmed_delete_removes_the_report
        post "/#{@id}/delete", { "confirm" => "yes" }

        assert_equal 302, last_response.status
        refute_path_exists store.dir_for(@id).to_s
    end

    # One store serves the whole process, so what matters is the
    # difference this made, not the total.
    def test_a_deleted_report_leaves_no_line_behind
        before = store.count

        post "/#{@id}/delete", { "confirm" => "yes" }

        assert_equal before - 1, store.count
        refute_includes listed, @id
    end

    def test_a_deleted_report_is_no_longer_a_page
        post "/#{@id}/delete", { "confirm" => "yes" }

        get "/#{@id}"

        assert_equal 404, last_response.status
    end

    # The one that would matter: deleting one report must not take the
    # others with it, since the index is rewritten to do it.
    def test_deleting_one_keeps_the_rest
        other  = store.save(TestSupport.document("message" => "the second one"))
        before = store.count

        post "/#{@id}/delete", { "confirm" => "yes" }

        assert_equal before - 1, store.count
        assert_includes listed, other
        refute_includes listed, @id
        assert_path_exists store.dir_for(other).to_s
    end

    def test_deleting_something_that_is_not_there_is_not_found
        post "/20260101T000000Z-deadbeef/delete", { "confirm" => "yes" }

        assert_equal 404, last_response.status
    end
end
