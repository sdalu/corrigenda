# frozen_string_literal: true

require "test_helper"

class HomeTest < CorrigendaTest
    def app = Corrigenda::Home

    def setup
        TestSupport.configure
    end

    # The prompts on the page, in the order they are written: the local
    # one first where there is a socket, the remote one always.
    def prompts
        last_response.body.scan(%r{<pre class="prompt">(.*?)</pre>}m).flatten
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
        assert_match %r{application/javascript},
                     last_response.headers["content-type"]
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

    # Public, as llms.txt and the manual are: every page that injects
    # the widget fetches it, visitors included. Apache lets this through
    # unauthenticated, and a cache header keeps a busy site from asking
    # for it every time.
    def test_the_widget_is_cacheable
        get "/corrigenda.js"

        assert_includes last_response.headers["cache-control"].to_s,
                        "max-age=300"
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

    # llms.txt is how an agent that knows only the convention finds its
    # footing: generated from the config, so what it links exists, and
    # carrying the mount so the link works from where it was fetched.
    def test_llms_txt_points_at_the_interface_when_there_is_one
        TestSupport.configure("api" => true)
        get "/llms.txt", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.corrigenda" }

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "# Corrigenda"
        assert_includes last_response.body,
                        "(/.corrigenda/agent/usage.md)"
        assert_includes last_response.body,
                        "(/.corrigenda/api/openapi.json)"
    ensure
        TestSupport.configure
    end

    def test_llms_txt_says_when_the_interface_is_off
        get "/llms.txt"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "switched off"
        refute_includes last_response.body, "openapi.json"
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

    # It names no site, and no longer restates the protocol either:
    # the loop lives in the manual the service serves, written once,
    # and the prompt's job is to say where it is.
    def test_the_prompt_points_at_the_manual_rather_than_restating_it
        TestSupport.configure("api" => true, "socket" => "/var/run/x/y.sock",
                              "sites" => %w[a.example.com b.example.com])
        get "/"
        prompt = prompts.first.to_s

        refute_includes prompt, "a.example.com"
        refute_includes prompt, "state=open"
        assert_includes prompt, "/agent/usage.md"
    ensure
        TestSupport.configure
    end

    # Where the agent runs decides what its prompt may assume, so there
    # are two: the socket is behind no login and can be handed commands,
    # while everything else arrives through Apache needing credentials
    # this page cannot supply — that one is pointed at llms.txt and left
    # to read its way in.
    def test_a_deployment_with_a_socket_offers_both_prompts
        TestSupport.configure("api" => true, "socket" => "/var/run/x/y.sock",
                              "endpoint" => "https://tools.example.com/.c")
        get "/"
        here, away = prompts

        assert_equal 2, prompts.size, "wanted a local prompt and a remote one"
        assert_includes here, "--unix-socket /var/run/x/y.sock"
        assert_includes away, "https://tools.example.com/.c/llms.txt"
        refute_includes away, "--unix-socket",
                        "the remote prompt cannot reach the socket"

        # And every path it names is written from the mount. Only the
        # socket sees this app unmounted: through Apache a bare /api
        # is a path on the host's root, where nothing answers.
        away.scan(%r{\S*/api\S*}).each do
            assert_match %r{\Ahttps://tools\.example\.com/\.c/api}, it,
                         "the remote prompt names an unmounted /api"
        end
        # The element, not the class name: the script that drives it
        # names the same class and is on the page either way.
        assert_includes last_response.body, %(<select class="a-prompt-pick")
    ensure
        TestSupport.configure
    end

    # The paths table is the page's account of what answers here, and
    # it went one release without llms.txt or the manual in it. Asserted
    # against the routes themselves rather than against a list written
    # twice: a route added and not described is the failure, and only
    # this direction catches it.
    #
    # NOT_LISTED is the deliberate silence. Each is a path a person has
    # no reason to visit -- an icon, the page they are already on, an
    # asset of the viewer, a page reached from the box that needs it.
    NOT_LISTED = ["/", "/icon.svg", "/signing", "/apidocs/:asset"].freeze

    def test_the_paths_table_describes_every_route_this_page_serves
        TestSupport.configure("api" => true,
                              "endpoint" => "https://tools.example.com/.c")
        get "/"
        listed = last_response.body.scan(%r{<td><code>(/[^<]*)</code></td>})
                                   .flatten

        Corrigenda::Home.routes["GET"].map { it[0].to_s }.each do |route|
            next if NOT_LISTED.include?(route)

            # /extension/:target is written for a reader, not as a
            # pattern: the table says /extension/… and means the same.
            wanted = route.sub(%r{/:[a-z]+\z}, "/…")

            assert_includes listed, wanted,
                            "#{route} answers but the table never says so"
        end
    ensure
        TestSupport.configure
    end

    # And the advice under the prompts names paths too, and they are read
    # by somebody about to write their own prompt — so they carry the
    # mount. A bare /api/ quoted there is the same defect as in a
    # prompt, one paragraph further down the page.
    def test_the_advice_under_the_prompts_names_mounted_paths
        TestSupport.configure("api" => true, "socket" => "/var/run/x/y.sock")
        get "/", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.corrigenda" }
        aside = last_response.body[%r{<p class="aside">(.*?)</p>}m, 1].to_s

        assert_includes aside, "<code>/.corrigenda/api/</code>"
        assert_includes aside, "/.corrigenda/llms.txt"
    ensure
        TestSupport.configure
    end

    # And no chooser where there is nothing to choose between: without a
    # socket the service is reached the same way from everywhere.
    def test_without_a_socket_there_is_one_prompt_and_no_chooser
        TestSupport.configure("api" => true,
                              "endpoint" => "https://tools.example.com/.c")
        get "/"

        assert_equal 1, prompts.size
        assert_includes prompts.first, "https://tools.example.com/.c/llms.txt"
        refute_includes last_response.body, %(<select class="a-prompt-pick")
    ensure
        TestSupport.configure
    end

    # Served from the checkout the service runs from, so the copy an
    # agent fetches matches the service it is talking to — and holds
    # what the prompt stopped carrying.
    def test_it_serves_the_agent_manual
        get "/agent/usage.md"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "state=open"
        assert_includes last_response.body, "not code review"
    end

    # And what it tells the agent to do follows what the deployment
    # actually allows, so a prompt cannot promise a permission the
    # endpoint will refuse. Only the grant: the discipline that goes
    # with it lives in the manual, asserted below.
    def test_the_prompt_says_what_the_agent_may_do
        TestSupport.configure("api" => true)
        get "/"

        assert_includes last_response.body, "You can only read here"

        TestSupport.configure("api" => { "write" => ["journal"] })
        get "/"

        # Wrapped where it is written, so the assertion has to be too:
        # the prompt lives inside a <pre> and its lines are chosen for
        # reading, not for matching.
        assert_match(/not change its\s+state/, last_response.body)

        TestSupport.configure("api" => { "write" => true })
        get "/"

        assert_match(/set its\s+state here/, last_response.body)
    ensure
        TestSupport.configure
    end

    # A picture of the page after the work is the half of a claim that
    # can be checked. The ask lived in every write-granted variant of
    # the prompt; it lives in the manual now, once, with the conditions
    # the picture itself cannot show — a comparison at another width
    # proves nothing, and nobody can tell unless the agent says.
    def test_the_manual_asks_for_the_picture_and_its_conditions
        get "/agent/usage.md"

        assert_includes last_response.body,
                        "beside the screenshot it was filed"
        assert_match(/`viewport` and `scheme`/, last_response.body)
    end

    # Both write-granted prompts hand the discipline to the manual by
    # name rather than restating it; the read-only one has nothing to
    # hold the agent to.
    def test_the_write_prompts_lean_on_the_manual
        ["journal", "state"].each do |grant|
            TestSupport.configure("api" => { "write" => [grant] })
            get "/"

            assert_match(/[Tt]he manual\s+says/,
                         last_response.body,
                         "#{grant}: the prompt never names the manual")
        end
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

    # A downloads folder collects these. Three files called
    # corrigenda-firefox.zip are three files nobody can tell apart,
    # including the one they are running, so the version travels in the
    # name -- read out of the package being sent.
    def test_the_download_is_named_with_its_version
        get "/extension/firefox"

        skip "no package built in this checkout" unless last_response.ok?

        version = JSON.parse(
            File.read("extension/dist/firefox/manifest.json"))["version"]

        assert_includes last_response.headers["content-disposition"].to_s,
                        "corrigenda-firefox-#{version}"
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
