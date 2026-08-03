# frozen_string_literal: true

require "test_helper"

# The Apache macro is generated from the same YAML the service reads,
# because the socket and the mount were written in both and a proxy
# pointed at the wrong socket answers 503 without saying why. Generated
# and committed: Apache includes the file straight from the repository,
# so a checkout has to be complete rather than buildable — and this is
# what keeps the committed copy honest.
class DeployTest < CorrigendaTest
    ROOT  = File.expand_path("..", __dir__)
    MACRO = File.join(ROOT, "deploy", "macro")

    def test_the_committed_macro_matches_the_config
        ok = system(MACRO, "--check", out: File::NULL, err: File::NULL)

        assert ok, "deploy/macro-corrigenda.conf is stale — run deploy/macro"
    end

    # What the generator exists to keep in step.
    def test_the_macro_carries_the_configured_socket_and_mount
        config = YAML.safe_load_file(File.join(ROOT, "deploy", "corrigenda.yml"))
        macro  = File.read(File.join(ROOT, "deploy", "macro-corrigenda.conf"))
        mount  = config.fetch("endpoint").sub(%r{\Ahttps?://[^/]+}, "")

        assert_includes macro, "unix:#{config.fetch('socket')}|"
        assert_includes macro, "<Location #{mount}>"
        assert_includes macro, %(RequestHeader set X-Forwarded-Prefix "#{mount}")
        # the one public path, under the same mount
        assert_includes macro, "<Location #{mount}/corrigenda.js>"
    end
end
