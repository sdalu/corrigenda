# frozen_string_literal: true

require "test_helper"

class IntakeTest < DebugFeedbackTest
    def app = DebugFeedback::Intake

    def setup
        TestSupport.configure
    end

    def test_health_answers
        get "/health"

        assert_predicate last_response, :ok?
    end

    # Apache proxies with the vhost's Host header. Sinatra's development
    # default permits only localhost and friends, which made every real
    # request 403 "Host not permitted" until host_authorization was set.
    def test_a_vhost_host_header_is_accepted
        get "/health", {}, { "HTTP_HOST" => "tools.sdalu.com" }

        assert_predicate last_response, :ok?
    end

    def test_a_vhost_host_header_is_accepted_on_a_report
        post "/", JSON.generate(TestSupport.document),
             { "CONTENT_TYPE" => "application/json",
               "HTTP_HOST" => "tools.sdalu.com" }

        assert_equal 201, last_response.status
    end

    def test_a_json_report_is_accepted_and_stored
        post_json(TestSupport.document)

        assert_equal 201, last_response.status
        id = JSON.parse(last_response.body).fetch("id")
        assert_equal "The caption overlaps the photo", store.read(id)["message"]
    end

    def test_the_reporter_comes_from_the_web_server
        post "/", JSON.generate(TestSupport.document),
             { "CONTENT_TYPE" => "application/json", "REMOTE_USER" => "sdalu" }

        assert_equal "sdalu", store.entries.first["reporter"]
    end

    # Behind ProxyPass there is no REMOTE_USER, only what Apache resends.
    def test_the_reporter_survives_the_proxy_hop
        post "/", JSON.generate(TestSupport.document),
             { "CONTENT_TYPE" => "application/json",
               "HTTP_X_REMOTE_USER" => "sdalu" }

        assert_equal "sdalu", store.entries.first["reporter"]
    end

    # The client gzips; the magic number is how the endpoint knows.
    def test_a_gzipped_report_is_accepted
        post "/", TestSupport.gzip(JSON.generate(TestSupport.document)),
             { "CONTENT_TYPE" => "application/json" }

        assert_equal 201, last_response.status
    end

    def test_a_non_json_body_is_a_400
        post "/", "not json at all", { "CONTENT_TYPE" => "application/json" }

        assert_equal 400, last_response.status
    end

    def test_a_document_failing_the_schema_is_a_422
        post_json(TestSupport.document("type" => "rant"))

        assert_equal 422, last_response.status
    end

    def test_an_oversized_body_is_refused_before_it_is_parsed
        TestSupport.configure("max_body" => 64)
        post_json(TestSupport.document("message" => "x" * 500))

        assert_equal 413, last_response.status
    ensure
        TestSupport.configure
    end

    def test_an_unlisted_site_is_refused
        TestSupport.configure("sites" => ["www.sdalu.com"])
        post_json(TestSupport.document)

        assert_equal 403, last_response.status
    ensure
        TestSupport.configure
    end

    def test_a_listed_site_is_accepted
        TestSupport.configure("sites" => ["www.alux.fr"])
        post_json(TestSupport.document)

        assert_equal 201, last_response.status
    ensure
        TestSupport.configure
    end

    def test_a_multipart_post_stores_its_screenshot
        Dir.mktmpdir do |dir|
            report = File.join(dir, "report.json")
            shot   = File.join(dir, "screenshot.webp")
            File.write(report, JSON.generate(TestSupport.document))
            File.binwrite(shot, "RIFF....WEBP".b)

            post "/", "report" => Rack::Test::UploadedFile.new(report, "application/json"),
                      "screenshot" => Rack::Test::UploadedFile.new(shot, "image/webp")

            assert_equal 201, last_response.status
            id = JSON.parse(last_response.body).fetch("id")
            assert_includes store.files(id), "screenshot.webp"
        end
    end

    # ----------------------------------------------------------------
    # Cross-origin: a site that does not mount this service posts to it
    # from its own origin, and the browser decides whether that happens.
    # ----------------------------------------------------------------
    def setup_allowlist
        TestSupport.configure("sites" => ["www.alux.fr", "tools.sdalu.com"])
    end

    def test_a_preflight_from_a_listed_site_is_answered
        setup_allowlist
        options "/", {}, { "HTTP_ORIGIN" => "https://www.alux.fr" }

        assert_equal 204, last_response.status
        assert_equal "https://www.alux.fr",
                     last_response.headers["access-control-allow-origin"]
        assert_equal "true",
                     last_response.headers["access-control-allow-credentials"]
        # gzip is why a preflight happens at all
        assert_includes last_response.headers["access-control-allow-headers"],
                        "Content-Encoding"
    end

    # A wildcard is refused by browsers once credentials are involved, so
    # the answer has to name the one origin — which means the answer
    # cannot be cached across origins.
    def test_the_answer_varies_by_origin
        setup_allowlist
        options "/", {}, { "HTTP_ORIGIN" => "https://www.alux.fr" }

        assert_includes last_response.headers["vary"].to_s, "Origin"
        refute_equal "*", last_response.headers["access-control-allow-origin"]
    end

    def test_a_preflight_from_an_unlisted_site_is_refused
        setup_allowlist
        options "/", {}, { "HTTP_ORIGIN" => "https://elsewhere.example" }

        assert_equal 404, last_response.status
        assert_nil last_response.headers["access-control-allow-origin"]
    end

    # http is not a scheme to hand credentials to, listed or not.
    def test_an_insecure_origin_is_refused
        setup_allowlist
        options "/", {}, { "HTTP_ORIGIN" => "http://www.alux.fr" }

        assert_equal 404, last_response.status
    end

    def test_a_cross_origin_report_carries_the_header_it_needs
        setup_allowlist
        post "/", JSON.generate(TestSupport.document),
             { "CONTENT_TYPE" => "application/json",
               "HTTP_ORIGIN" => "https://www.alux.fr" }

        assert_equal 201, last_response.status
        assert_equal "https://www.alux.fr",
                     last_response.headers["access-control-allow-origin"]
    end

    # Same-origin posts have no Origin to allow and must not be given
    # one: the header is for the browser's benefit, and inventing it
    # says something untrue about who may read the answer.
    def test_a_same_origin_report_gets_no_cors_header
        setup_allowlist
        post_json(TestSupport.document)

        assert_equal 201, last_response.status
        assert_nil last_response.headers["access-control-allow-origin"]
    ensure
        TestSupport.configure
    end
end
