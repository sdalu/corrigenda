# frozen_string_literal: true

require "test_helper"

class HomeTest < DebugFeedbackTest
    def app = DebugFeedback::Home

    def setup
        TestSupport.configure
    end

    def test_the_mount_point_is_a_page_not_a_404
        get "/"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "Debug feedback"
    end

    # Built in the browser from location.origin, because the app is not
    # told its public URL by the proxy.
    def test_the_bookmarklet_is_assembled_client_side
        get "/"

        assert_includes last_response.body, "location.origin"
        assert_includes last_response.body, "/common/js/debug-feedback.js"
    end

    def test_it_links_to_the_review_ui_relatively
        get "/"

        assert_includes last_response.body, %(href="review/")
    end

    # The suite shares one store, so a count is only meaningful relative
    # to whatever the tests before this one already put there. Asserting
    # "1 stored" passed or failed depending on the random seed.
    def test_it_reports_how_many_are_stored
        before = store.count
        store.save(TestSupport.document)
        get "/"

        assert_includes last_response.body, "#{before + 1} stored"
    end

    def test_it_names_the_allowlist_when_there_is_one
        TestSupport.configure("sites" => ["tools.sdalu.com"])
        get "/"

        assert_includes last_response.body, "tools.sdalu.com"
    ensure
        TestSupport.configure
    end
end
