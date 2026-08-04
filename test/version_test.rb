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

    # ----------------------------------------------------------------
    # The helper contract: what the add-on provides and the widget
    # requires. Two numbers about the same thing -- the shape of the
    # ping and capture exchanges -- carried by two artifacts that are
    # installed and served separately, so they are allowed to differ in
    # the field. What they may not do is ship from one checkout unable
    # to talk to each other.
    # ----------------------------------------------------------------
    BRIDGE = File.join(ROOT, "extension", "content.js")

    def provided = File.read(BRIDGE)[/const HELPER\s*=\s*(\d+)/, 1].to_i
    def required = File.read(CLIENT)[/const HELPER_REQUIRED = (\d+)/, 1].to_i

    def test_the_helper_numbers_are_declared
        assert_operator provided, :>=, 1,
                        "extension/content.js declares no HELPER"
        assert_operator required, :>=, 1,
                        "the widget declares no HELPER_REQUIRED"
    end

    def test_the_add_on_provides_what_the_widget_requires
        assert_operator provided, :>=, required,
                        "the add-on in this checkout (helper #{provided}) is " \
                        "below what its own widget requires " \
                        "(#{required}), so " \
                        "the widget would ignore it and take the share dialog"
    end

    # The add-on keeps a version of its own -- it is installed rather
    # than served, so a browser may be carrying any of them -- but the
    # two packages are one add-on and must not disagree with each other.
    def test_both_manifests_are_the_same_add_on
        assert_equal manifest("firefox").fetch("version"),
                     manifest("chrome").fetch("version"),
                     "the Firefox and Chrome packages claim different versions"
    end

    # The add-on id is permanent -- a signature is bound to it -- so it
    # is the worst place in the repository for a hostname belonging to
    # whoever happened to build it first. A UUID names nobody.
    def test_the_add_on_id_names_nobody
        id = manifest("firefox")
             .dig("browser_specific_settings", "gecko", "id")

        assert_match(/\A\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}\z/i, id,
                     "the add-on id should be a UUID, not an address: #{id}")
    end

    def test_the_manifests_carry_a_release_number
        assert_match(/\A\d+\.\d+(\.\d+)?\z/,
                     manifest("firefox").fetch("version"))
    end

    # The landing page reads the version out of the built package, which
    # is the honest answer to "which build is this download" only while
    # the build is current. rake addon:version rebuilds for this reason.
    def test_a_built_package_is_not_older_than_its_manifest
        %w[firefox chrome].each do |target|
            built = File.join(ROOT, "extension", "dist", target,
                              "manifest.json")
            next unless File.exist?(built)

            assert_equal manifest(target).fetch("version"),
                         JSON.parse(File.read(built)).fetch("version"),
                         "extension/dist/#{target} was built before the " \
                         "version was raised -- run extension/build"
        end
    end
end
