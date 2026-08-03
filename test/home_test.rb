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
        TestSupport.configure("sites" => ["tools.example.com"])
        get "/"

        assert_includes last_response.body, "tools.example.com"
    ensure
        TestSupport.configure
        end

    # Whoever started the service read one line, hours ago; whoever is
    # reading this page is asking now. Both sentences come from Config,
    # so they cannot describe the same deployment differently.
    def test_the_page_says_the_api_is_off_when_it_is
    get "/"

    assert_includes last_response.body, "No <code>api:</code> key"
end

def test_the_page_says_what_the_api_allows
    TestSupport.configure("api" => { "write" => true })
    get "/"

    assert_includes last_response.body,
                    "may record work, archive, set states"
ensure
    TestSupport.configure
end

    def test_a_read_only_api_says_so
    TestSupport.configure("api" => true)
    get "/"

    assert_includes last_response.body, "read-only"
ensure
    TestSupport.configure
end

# The prompt is on the page rather than in the README because this
# page knows the answers: the socket this service listens on, a site
# it accepts reports about, and what an agent may do here.
def test_no_api_no_prompt
    get "/"

    refute_includes last_response.body, "Setting an agent to work"
end

def test_the_prompt_carries_this_deployment_s_own_socket
    TestSupport.configure("api" => true, "socket" => "/var/run/x/y.sock")
    get "/"

    assert_includes last_response.body, "Setting an agent to work"
    assert_includes last_response.body, "--unix-socket /var/run/x/y.sock"
ensure
    TestSupport.configure
end

# It names no site. An estate has as many as it has, and taking one off
# the top of the list tells an agent to work on whichever happened to be
# written first; the filter is the useful thing to teach instead.
def test_the_prompt_teaches_the_filter_rather_than_naming_a_site
    TestSupport.configure("api" => true,
                          "sites" => %w[a.example.com b.example.com])
    get "/"
    prompt = last_response.body[/<pre class="prompt">(.*?)<\/pre>/m, 1].to_s

    refute_includes prompt, "a.example.com"
    assert_includes prompt, "state=open"
    assert_includes prompt, "site="
ensure
    TestSupport.configure
end

# And what it tells the agent to do follows what the deployment
# actually allows, so a prompt cannot promise a permission the
# endpoint will refuse.
def test_the_prompt_says_what_the_agent_may_do
    TestSupport.configure("api" => true)
    get "/"

    assert_includes last_response.body, "You can only read here"

    TestSupport.configure("api" => { "write" => ["journal"] })
    get "/"

    assert_includes last_response.body, "cannot change a report"

    TestSupport.configure("api" => { "write" => true })
    get "/"

    assert_includes last_response.body, "do not mark"
ensure
    TestSupport.configure
end

# The one thing on this page that would be a secret.
def test_the_prompt_never_prints_the_token
    TestSupport.configure("api" => { "write" => ["journal"],
                                     "token" => "s3cret-abc" })
    get "/"

    refute_includes last_response.body, "s3cret-abc"
    assert_includes last_response.body, "which you give it yourself"
ensure
    TestSupport.configure
end

    # The schema viewer. A tab leading to a 404 is worse than no tab, so
    # both the tab and the page follow the deployment: with no `api:`
    # key the endpoint answers 404 to everything and there is nothing to
    # render.
    def test_no_api_no_tab_and_no_viewer
        get "/"

        refute_includes last_response.body, "/apidocs"

        get "/apidocs"

        assert_equal 404, last_response.status
        end

    def test_the_tab_and_the_viewer_arrive_with_the_endpoint
        TestSupport.configure("api" => true)
        get "/"

        assert_includes last_response.body, "apidocs"

        get "/apidocs"

        assert_equal 200, last_response.status
        assert_includes last_response.body, "SwaggerUIBundle"
        assert_includes last_response.body, "/api/openapi.json"
    ensure
        TestSupport.configure
        end

    # Vendored, whitelisted by name: the path is a path component, and
    # the directory holds a licence and a README nobody should be able
    # to pull through this route.
    def test_the_viewer_serves_its_two_files_and_nothing_else
        TestSupport.configure("api" => true)

        get "/apidocs/swagger-ui.css"

        assert_equal 200, last_response.status
        assert_match(%r{^text/css}, last_response.content_type)

        get "/apidocs/README.md"

        assert_equal 404, last_response.status

        get "/apidocs/..%2F..%2FGemfile"

        assert_equal 404, last_response.status
    ensure
        TestSupport.configure
        end
end
