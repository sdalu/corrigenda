# frozen_string_literal: true

require "test_helper"

# The mounted stack as config.ru builds it: the prefix middleware has to
# sit outside Rack::URLMap, which appends its own segment to SCRIPT_NAME.
class PrefixTest < DebugFeedbackTest
    def app
        Rack::Builder.new do
            use DebugFeedback::Prefix
            map("/review") { run DebugFeedback::Review }
        end.to_app
    end

    def setup
        TestSupport.configure
        @id = store.save(TestSupport.document)
    end

    def test_links_carry_the_prefix_the_proxy_stripped
        get "/review/", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.debug-feedback" }

        assert_includes last_response.body,
                        %(href="/.debug-feedback/review/#{@id}")
    end

    # ProxyPreserveHost is off by default, so an absolute URL would name
    # the backend rather than the vhost.
    def test_links_are_paths_not_absolute_urls
        get "/review/", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.debug-feedback" }

        refute_includes last_response.body, "http://localhost/review"
        refute_includes last_response.body, "http://example.org"
    end

# The redirect after a state change is what sent a browser to
# http://<vhost>/... : Sinatra re-absolutises Location against the
# host it believes it has, which is the backend, over http.
def test_the_state_redirect_is_a_path_not_an_absolute_url
    post "/review/#{@id}/state", { "state" => "wontfix" },
         { "HTTP_X_FORWARDED_PREFIX" => "/.debug-feedback" }

    assert_equal "/.debug-feedback/review/#{@id}",
                 last_response.headers["location"]
end

    def test_without_the_header_nothing_changes
        get "/review/"

        assert_includes last_response.body, %(href="/review/#{@id}")
    end

    def test_a_trailing_slash_in_the_header_is_not_doubled
        get "/review/", {}, { "HTTP_X_FORWARDED_PREFIX" => "/.debug-feedback/" }

        refute_includes last_response.body, "//review"
    end
end
