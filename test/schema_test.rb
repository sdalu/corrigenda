# frozen_string_literal: true

require "test_helper"

class SchemaTest < Minitest::Test
    def test_a_minimal_report_validates
        document = TestSupport.document

        assert_equal document, Corrigenda.validate(document)
    end

    def test_unknown_keys_survive_so_a_newer_client_is_not_rejected
        document = TestSupport.document("hologram" => { "depth" => 3 })

        assert_equal 3, Corrigenda.validate(document).dig("hologram", "depth")
    end

    def test_a_missing_schema_version_is_refused
        document = TestSupport.document
        document.delete("schema")

        assert_raises(Corrigenda::PayloadError) { Corrigenda.validate(document) }
    end

    def test_a_future_schema_version_is_refused
        assert_raises(Corrigenda::PayloadError) do
            Corrigenda.validate(TestSupport.document("schema" => 2))
        end
    end

    def test_an_unknown_type_is_refused
        assert_raises(Corrigenda::PayloadError) do
            Corrigenda.validate(TestSupport.document("type" => "rant"))
        end
    end

    def test_a_page_without_a_url_is_refused
        assert_raises(Corrigenda::PayloadError) do
            Corrigenda.validate(TestSupport.document("page" => { "site" => "x" }))
        end
    end
end
