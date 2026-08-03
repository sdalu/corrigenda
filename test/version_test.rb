# frozen_string_literal: true

require "json"

require "test_helper"

# The number is written in more than one file because more than one file
# is shipped, and none of them can read a Ruby constant: the widget is a
# static asset, the manifests are JSON a browser reads. So the thing to
# hold is not a single source but the agreement between them.
class VersionTest < CorrigendaTest
    ROOT   = File.expand_path("..", __dir__)
    CLIENT = File.join(ROOT, "client", "corrigenda.js")

    def manifest(target)
        JSON.parse(File.read(
                       File.join(ROOT, "extension", "manifest.#{target}.json")))
    end

    def test_the_version_is_a_release_number
        assert_match(/\A\d+\.\d+\.\d+\z/, Corrigenda::VERSION)
    end

    # The client is served by the endpoint that reads its payloads, so a
    # page cannot be running a widget the service has never seen. Saying
    # a version it does not have would make that guarantee a lie.
    def test_the_widget_says_the_version_that_serves_it
        said = File.read(CLIENT)[/const VERSION = "([^"]+)"/, 1]

        assert_equal Corrigenda::VERSION, said,
                     "client/corrigenda.js and Corrigenda::VERSION disagree"
    end

    def test_the_widget_stamps_it_on_the_host_element
        assert_includes File.read(CLIENT), "host.dataset.version = VERSION;"
    end

    # The add-on keeps a version of its own -- it is installed rather
    # than served, so a browser may be carrying any of them -- but the
    # two packages are one add-on and must not disagree with each other.
    def test_both_manifests_are_the_same_add_on
        assert_equal manifest("firefox").fetch("version"),
                     manifest("chrome").fetch("version"),
                     "the Firefox and Chrome packages claim different versions"
    end

    def test_the_manifests_carry_a_release_number
        assert_match(/\A\d+\.\d+(\.\d+)?\z/, manifest("firefox").fetch("version"))
    end
end
