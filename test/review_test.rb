# frozen_string_literal: true

require "test_helper"

class ReviewTest < DebugFeedbackTest
    def app = DebugFeedback::Review

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
    # which media query had to hold for the rule to apply.
    def test_the_detail_shows_the_cascade_context
        get "/#{@id}"

        assert_includes last_response.body, "<li>@layer components</li>"
        assert_includes last_response.body, "<li>@media (width &gt; 20rem)</li>"
        assert_includes last_response.body, %(<li class="is-selector">.caption)
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

    assert_includes last_response.body, %(<span class="chip" title="fragment">E</span>)
    assert_includes last_response.body, %(<span class="chip" title="rules">R</span>)
    refute_includes last_response.body, %(title="computed")
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
end
