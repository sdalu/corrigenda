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
end
