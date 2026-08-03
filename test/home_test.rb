# frozen_string_literal: true

require "test_helper"

class HomeTest < CorrigendaTest
    def app = Corrigenda::Home

    def setup
        TestSupport.configure
    end

    def test_the_mount_point_is_a_page_not_a_404
        get "/"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "Corrigenda"
    end

    # Built in the browser from location.origin, because the app is not
    # told its public URL by the proxy. The path itself comes from the
    # mount, so this test sees it without a prefix and the deployed page
    # sees /.corrigenda/corrigenda.js.
    def test_the_bookmarklet_is_assembled_client_side
        get "/"

        assert_includes last_response.body, "location.origin"
        assert_includes last_response.body, "/corrigenda.js"
    end

    # Served by this app rather than from the shared asset tree, so the
    # client and the endpoint that reads its reports ship together.
    def test_it_serves_the_widget
        get "/corrigenda.js"

        assert_predicate last_response, :ok?
        assert_match %r{application/javascript}, last_response.headers["content-type"]
        # send_file hands back binary; the file is UTF-8 and says so in
        # the header, so compare on equal terms rather than letting Ruby
        # refuse to mix the two encodings.
        assert_includes last_response.body.force_encoding("UTF-8"),
                        "page-defect reporting widget"
    end

# Written for whoever runs the service, and reachable from the box
# that tells a reader their install is temporary.
def test_the_signing_page_answers
    get "/signing"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "AMO_JWT_ISSUER"
    assert_includes last_response.body, "extension"
end

def test_the_add_on_box_links_to_it
    get "/"

    assert_includes last_response.body, %(href="/signing")
end

    # The one public path: every page that injects the widget fetches it,
    # visitors included. Apache lets this through unauthenticated, and a
    # cache header keeps a busy site from asking for it every time.
    def test_the_widget_is_cacheable
        get "/corrigenda.js"

        assert_includes last_response.headers["cache-control"].to_s, "max-age=300"
        refute_nil last_response.headers["last-modified"]
    end

    # Built from the mount root, so the same masthead works from Home
    # (mounted at /) and Review (mounted at /review).
    def test_it_links_to_the_review_ui_from_the_mount_root
        get "/", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.corrigenda" }

        assert_includes last_response.body, %(href="/.corrigenda/review/")
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
