# frozen_string_literal: true

require "test_helper"

class ReviewTest < CorrigendaTest
    def app = Corrigenda::Review

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
            reporter: "sdalu"
        )
    end

    def test_the_listing_shows_a_report
        get "/"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "www.alux.fr"
    end

    def test_the_listing_is_reachable_under_a_vhost_host_header
        get "/", {}, { "HTTP_HOST" => "tools.sdalu.com" }

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
                        "&lt;base href=&quot;https://www.alux.fr/&quot;&gt;"
    end
end
