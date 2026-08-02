# frozen_string_literal: true

require "test_helper"

class StoreTest < FeedbackTest
    def setup
        @store = DebugFeedback::Store.new(Dir.mktmpdir("store-test"))
    end

    def test_save_returns_a_sortable_dated_id
        id = @store.save(TestSupport.document)

        assert_match(/\A\d{8}T\d{6}Z-[0-9a-f]{8}\z/, id)
    end

    def test_report_lands_in_a_year_month_directory
        id  = @store.save(TestSupport.document)
        dir = @store.dir_for(id)

        assert_path_exists(dir / "report.json")
        assert_equal [id[0, 4], id[4, 2]],
                     [dir.parent.parent.basename.to_s, dir.parent.basename.to_s]
    end

    def test_read_returns_the_document_verbatim
        document = TestSupport.document("message" => "wrong colour")
        id       = @store.save(document)

        assert_equal document, @store.read(id)
    end

    def test_read_is_nil_for_an_unknown_id
        assert_nil @store.read("20260101T000000Z-deadbeef")
    end

    def test_bad_ids_are_refused_rather_than_escaping_the_store
        assert_raises(DebugFeedback::StorageError) { @store.dir_for("../../etc") }
    end

    def test_attachments_are_written_beside_the_report
        id = @store.save(TestSupport.document,
                         files: { "screenshot.webp" => "RIFF-ish".b })

        assert_includes @store.files(id), "screenshot.webp"
    end

    def test_state_defaults_to_open_and_can_be_marked
        id = @store.save(TestSupport.document)
        assert_equal "open", @store.state(id)

        @store.mark(id, "fixed")
        assert_equal "fixed", @store.state(id)
    end

    def test_unknown_states_are_refused
        id = @store.save(TestSupport.document)

        assert_raises(DebugFeedback::StorageError) { @store.mark(id, "maybe") }
    end

    def test_entries_are_newest_first_and_carry_current_state
        first  = @store.save(TestSupport.document("message" => "one"))
        second = @store.save(TestSupport.document("message" => "two"))
        @store.mark(first, "wontfix")

        entries = @store.entries

        assert_equal [second, first], entries.map { it["id"] }
        assert_equal "wontfix", entries.last["state"]
    end

    def test_entries_is_empty_before_anything_is_reported
        assert_empty DebugFeedback::Store.new(Dir.mktmpdir).entries
    end
end
