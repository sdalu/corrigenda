# frozen_string_literal: true

require "English"
require "tmpdir"
require "yaml"

require "test_helper"

# Apache's own configuration is generated from the YAML the service
# reads, because the socket, the mount and the authentication were
# written in both places and the failures that produces say nothing
# about themselves: a proxy pointed at the wrong socket answers 503 with
# the service running, and an auth block that disagrees with the
# deployment either locks the staff out or lets the world in.
#
# Neither the generated file nor the config is tracked — one is a copy
# of the other, and the other names a deployment. What a checkout has is
# the template and the generator, so that is what these exercise.
class DeployTest < CorrigendaTest
    ROOT     = File.expand_path("..", __dir__)
    MACRO    = File.join(ROOT, "deploy", "macro")
    CONFIG   = File.join(ROOT, "deploy", "corrigenda.yml")
    TEMPLATE = File.join(ROOT, "deploy", "corrigenda-template.yml")
    TARGET   = File.join(ROOT, "deploy", "macro-corrigenda.conf")

    # What a new deployment starts from has to work.
    def test_the_template_generates
        out = IO.popen([MACRO, "--stdout", "--config", TEMPLATE], &:read)

        assert_predicate $CHILD_STATUS, :success?, "the template does not generate"
        assert_includes out, "<Macro CorrigendaEndpoint>"
    end

    def test_a_missing_config_says_what_to_copy
        Dir.mktmpdir do |dir|
            out = IO.popen([MACRO, "--stdout", "--config",
                            File.join(dir, "absent.yml")],
                           err: %i[child out], &:read)

            refute_predicate $CHILD_STATUS, :success?
            assert_includes out, "corrigenda-template.yml"
        end
    end

    # The three fields the generator exists to keep in step.
    def test_the_macro_carries_the_socket_the_mount_and_the_provider
        source = File.exist?(CONFIG) ? CONFIG : TEMPLATE
        config = YAML.safe_load_file(source)
        macro  = IO.popen([MACRO, "--stdout", "--config", source], &:read)
        mount  = config.fetch("endpoint").sub(%r{\Ahttps?://[^/]+}, "")

        assert_includes macro, "unix:#{config.fetch('socket')}|"
        assert_includes macro, "<Location #{mount}>"
        assert_includes macro, %(RequestHeader set X-Forwarded-Prefix "#{mount}")
        # the one public path, under the same mount
        assert_includes macro, "<Location #{mount}/corrigenda.js>"
        assert_includes macro, config.dig("auth", "url").to_s
    end

    # ./run writes it at every start; if one is lying about on a
    # development checkout it should still agree with the config beside it.
    def test_a_generated_file_on_disk_is_current
        skip "not generated in this checkout" unless File.exist?(TARGET)
        skip "no deployment config here"      unless File.exist?(CONFIG)

        ok = system(MACRO, "--check", out: File::NULL, err: File::NULL)

        assert ok, "deploy/macro-corrigenda.conf is stale — run deploy/macro"
    end

    # ----------------------------------------------------------------
    # Providers. Apache enforces who may reach the endpoint, so the block
    # that says so lives in the config the service reads.
    # ----------------------------------------------------------------
    def render(auth)
        Dir.mktmpdir do |dir|
            path = File.join(dir, "corrigenda.yml")
            File.write(path, YAML.dump(
                                 "socket" => "/var/run/corrigenda/corrigenda.sock",
                                 "endpoint" => "https://tools.example.com/.corrigenda",
                                 "auth" => auth))

            out = IO.popen([MACRO, "--stdout", "--config", path], &:read)
            assert_predicate $CHILD_STATUS, :success?, "macro refused #{auth.inspect}"
            out
        end
    end

    def test_ldap_carries_its_url_and_requirement
        conf = render("type" => "ldap", "url" => "ldap://ldap.test/dc=x",
                      "realm" => "Staff", "require" => "ldap-group cn=staff")

        assert_includes conf, "AuthBasicProvider   ldap"
        assert_includes conf, "AuthLDAPURL         ldap://ldap.test/dc=x"
        assert_includes conf, %(AuthName            "Staff")
        assert_includes conf, "Require         ldap-group cn=staff"
    end

    def test_a_password_file_is_a_provider_too
        conf = render("type" => "file", "file" => "/usr/local/etc/corrigenda.htpasswd")

        assert_includes conf, "AuthBasicProvider   file"
        assert_includes conf, "AuthUserFile        /usr/local/etc/corrigenda.htpasswd"
        refute_includes conf, "ldap"
    end

    # Saying it is allowed; the preflight exemption then has nothing to
    # exempt, and the whole endpoint is open.
    def test_none_asks_nobody
        conf = render("type" => "none")

        assert_includes conf, "Require all granted"
        refute_includes conf, "AuthBasicProvider"
        refute_includes conf, "LimitExcept"
    end

    # The one thing that must survive every change of provider: a CORS
    # preflight carries no credentials and cannot be given any, so gating
    # it turns a cross-origin report into a 401 the page never sees.
    def test_the_preflight_is_never_gated
        %w[ldap file].each do |type|
            extra = type == "ldap" ? { "url" => "ldap://x/" } : { "file" => "/x" }
            conf  = render({ "type" => type }.merge(extra))

            assert_includes conf, "<LimitExcept OPTIONS>",
                            "#{type} would demand credentials on a preflight"
        end
    end

    # A missing block is a mistake, not a licence to serve it openly.
    def test_no_auth_block_is_refused
        Dir.mktmpdir do |dir|
            path = File.join(dir, "corrigenda.yml")
            File.write(path, YAML.dump(
                                 "socket" => "/s.sock",
                                 "endpoint" => "https://example.test/.corrigenda"))

            ok = system(MACRO, "--stdout", "--config", path,
                        out: File::NULL, err: File::NULL)

            refute ok, "a config with no auth block generated a macro anyway"
        end
    end
end
