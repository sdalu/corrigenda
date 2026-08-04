# frozen_string_literal: true

require "test_helper"

# This repository is the program, not the deployment that runs it. The
# hosts, the accounts and the directory server of any one installation
# live in files that are not tracked -- deploy/corrigenda.yml, and
# whatever a checkout keeps beside it -- so what is committed can be
# handed to anyone.
#
# Past commits are what they are; this is about the next one.
class TrackedFilesTest < CorrigendaTest
    ROOT = File.expand_path("..", __dir__)

    # Hostnames of the estate this was written for. Bare words are not
    # listed on purpose: "sdalu" appears in the MoXoW project URL, which
    # is a real reference to a real project and is meant to be there.
    PRIVATE = /\b (?:[\w-]+\.)*
                  (?:sdalu\.com|alux\.fr|kuiristo\.eu|moxow\.org) \b/ix

    # Whatever a test needs that a fixture cannot be: an untracked file
    # beside the tracked ones. Nothing here reads it today -- the suites
    # run entirely on example.com -- but it is where a real host belongs
    # if one is ever genuinely required.
    LOCAL = File.join(ROOT, "test", "local.rb")

    def tracked
        Dir.chdir(ROOT) { `git ls-files`.lines(chomp: true) }
    end

    def test_no_tracked_file_names_a_private_host
        git = File.join(ROOT, ".git")
        skip "not a git checkout" unless File.directory?(git)

        offenders = tracked.filter_map do |rel|
            path = File.join(ROOT, rel)
            next unless File.file?(path)

            # Icons and packages are tracked too, and a PNG is not text.
            body = File.read(path)
            next unless body.valid_encoding?

            found = body.scan(PRIVATE).uniq
            "#{rel}: #{found.join(', ')}" unless found.empty?
        end

        assert_empty offenders, <<~SAY
            A tracked file names a host of the deployment this was written
            for. Use example.com, or put what you need in an untracked
            #{LOCAL.sub("#{ROOT}/", "")}.
        SAY
    end

    # The one reference that is meant to be there, asserted so that a
    # future sweep for hostnames cannot quietly take it out.
    def test_the_moxow_link_is_kept
        page = File.read(File.join(ROOT, "views", "home.erb"))

        assert_includes page, "https://gitlab.com/sdalu/moxow",
                        "the link to MoXoW is deliberate and should stay"
    end

    def test_the_local_file_is_not_tracked
        git = File.join(ROOT, ".git")
        skip "not a git checkout" unless File.directory?(git)

        refute_includes tracked, "test/local.rb",
                        "test/local.rb is for what must not be committed"
    end
end
