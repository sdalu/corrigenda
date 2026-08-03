# frozen_string_literal: true

require "test_helper"

class StoreTest < CorrigendaTest
    def setup
        @store = Corrigenda::Store.new(Dir.mktmpdir("store-test"))
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
        assert_raises(Corrigenda::StorageError) { @store.dir_for("../../etc") }
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

        assert_raises(Corrigenda::StorageError) { @store.mark(id, "maybe") }
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
        assert_empty Corrigenda::Store.new(Dir.mktmpdir).entries
    end

# The trail. A state that changed and nobody can say why is the thing
# this exists to prevent, so the store writes the entry itself rather
# than trusting every caller to remember.
def test_a_state_change_records_itself
    id = @store.save(TestSupport.document)
    @store.mark(id, "fixed", by: "sdalu")

    entry = @store.journal(id).last

    assert_equal "state", entry["kind"]
    assert_equal "open → fixed", entry["note"]
    assert_equal "sdalu", entry["by"]
end

def test_marking_the_same_state_twice_records_once
    id = @store.save(TestSupport.document)
    @store.mark(id, "fixed")
    @store.mark(id, "fixed")

    assert_equal 1, @store.journal(id).size
end

def test_archiving_and_unarchiving_are_both_recorded
    id = @store.save(TestSupport.document)
    @store.archive(id)
    @store.archive(id, yes: false)

    assert_equal ["archived", "back in the working list"],
                 @store.journal(id).map { it["note"] }
end

# Two different facts: what the server knows, and what the caller
# calls itself. Kept apart because the second is not identification.
def test_a_note_keeps_the_actor_and_the_agent_apart
    id = @store.save(TestSupport.document)
    @store.record(id, "raised the contrast to 4.8:1",
                  by: "sdalu", agent: "claude", refs: ["abc1234"])

    entry = @store.journal(id).last

    assert_equal "note", entry["kind"]
    assert_equal "sdalu", entry["by"]
    assert_equal "claude", entry["agent"]
    assert_equal ["abc1234"], entry["refs"]
end

def test_an_empty_note_records_nothing
    id = @store.save(TestSupport.document)

    assert_raises(Corrigenda::StorageError) { @store.record(id, "   ") }
    assert_empty @store.journal(id)
end

# A line can carry a picture: what the page looked like after the step,
# to be read beside the one the report was filed with.
def test_a_journal_line_can_carry_a_picture
    id = @store.save(TestSupport.document)
    entry = @store.record(id, "raised the contrast",
                          shot: { type: "image/webp", bytes: "RIFF-after".b })

    assert_equal "shot-1.webp", entry["shot"]
    assert_equal "RIFF-after", (@store.dir_for(id) / "shot-1.webp").binread
    assert_equal ["shot-1.webp"], @store.shots(id)
end

# Numbered from the pictures on disk, not from the length of the
# journal: most lines carry none, and counting lines would hand the
# same name out twice.
def test_pictures_are_numbered_as_they_arrive
    id = @store.save(TestSupport.document)
    @store.record(id, "first look", shot: { type: "image/png", bytes: "PNG".b })
    @store.record(id, "nothing to show")
    entry = @store.record(id, "after the fix",
                          shot: { type: "image/webp", bytes: "RIFF".b })

    assert_equal "shot-2.webp", entry["shot"]
    assert_equal %w[shot-1.png shot-2.webp], @store.shots(id)
end

def test_a_picture_of_an_unknown_kind_is_refused
    id = @store.save(TestSupport.document)

    assert_raises(Corrigenda::StorageError) do
        @store.record(id, "a note", shot: { type: "image/gif", bytes: "GIF".b })
    end
    assert_empty @store.journal(id)
end

def test_a_picture_past_the_ceiling_is_refused
    id = @store.save(TestSupport.document)
    huge = { type: "image/webp",
             bytes: "x".b * (Corrigenda::Store::MAX_SHOT + 1) }

    assert_raises(Corrigenda::StorageError) { @store.record(id, "big", shot: huge) }
    assert_empty @store.journal(id)
end

def test_the_journal_is_not_an_attachment
    id = @store.save(TestSupport.document,
                     files: { "screenshot.webp" => "RIFF".b })
    @store.record(id, "looked at it")

    assert_equal ["report.json", "screenshot.webp"],
                 @store.attachments(id).sort
end

    # Retention. The clock is not stopped for the tests: a report is aged
    # by moving the marker's mtime and by asking about a `now` further
    # along, which is what the store itself reads.
    def days_ago(count) = Time.now.utc - (count * 86_400)

    def archived_days_ago(id, count)
        @store.archive(id)
        marker = @store.dir_for(id) / Corrigenda::Store::ARCHIVE
        File.utime(days_ago(count), days_ago(count), marker)
        id
    end

    def test_nothing_expires_without_rules
        @store.save(TestSupport.document)

        assert_empty @store.expired(nil)
        assert_empty @store.expired({})
    end

    def test_the_archived_rule_counts_from_the_archiving
        old   = archived_days_ago(@store.save(TestSupport.document), 100)
        young = archived_days_ago(@store.save(TestSupport.document), 10)
        open  = @store.save(TestSupport.document)

        going = @store.expired({ "archived" => 90 })

        assert_equal [old], going.map { it[:id] }
        assert_equal "archived", going.first[:rule]
        assert_equal 100, going.first[:days]
        refute_includes going.map { it[:id] }, young
        refute_includes going.map { it[:id] }, open
    end

    # The id carries the filing time, so ageing a report by `any` needs no
    # file touched -- which is also why a report whose index line was lost
    # is still datable.
    def test_the_any_rule_counts_from_the_filing
        id = "20200101T000000Z-0badcafe"
        FileUtils.mkdir_p(@store.dir_for(id))

        going = @store.expired({ "any" => 365 })

        assert_equal [id], going.map { it[:id] }
        assert_equal "any", going.first[:rule]
    end

    # A report old enough for both is reported under the rule about a
    # decision somebody made, not the one about the calendar.
    def test_archived_is_the_reason_when_both_rules_match
        id = archived_days_ago(@store.save(TestSupport.document), 100)

        going = @store.expired({ "archived" => 90, "any" => 1 })

        assert_equal [{ id:, rule: "archived", days: 100 }], going
    end

    def test_purge_takes_the_directory_and_the_index_line_together
        gone = archived_days_ago(@store.save(TestSupport.document), 100)
        kept = @store.save(TestSupport.document)

        @store.purge({ "archived" => 90 })

        refute_path_exists @store.dir_for(gone)
        assert_equal [kept], @store.entries.map { it["id"] }
        assert_equal 1, @store.count
    end

    def test_purge_says_what_it_took
        id = archived_days_ago(@store.save(TestSupport.document), 91)

        assert_equal [{ id:, rule: "archived", days: 91 }],
                     @store.purge({ "archived" => 90 })
    end

    # An emptied month is not left behind as a directory; a month with
    # anything still in it is untouched.
    def test_purge_prunes_the_months_it_empties
        id  = "20200101T000000Z-0badcafe"
        dir = @store.dir_for(id)
        FileUtils.mkdir_p(dir)

        @store.purge({ "any" => 365 })

        refute_path_exists dir.parent
        refute_path_exists dir.parent.parent
    end

    def test_purge_leaves_a_month_that_still_has_reports
        old = "20200101T000000Z-0badcafe"
        FileUtils.mkdir_p(@store.dir_for(old))
        young = "20200131T000000Z-0badbeef"
        FileUtils.mkdir_p(@store.dir_for(young))

        # Only the first is old enough at this `now`.
        @store.purge({ "any" => 365 }, now: Time.utc(2021, 1, 15))

        assert_path_exists @store.dir_for(young)
        refute_path_exists @store.dir_for(old)
    end
end
