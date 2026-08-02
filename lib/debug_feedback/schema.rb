# frozen_string_literal: true

require "dry-schema"

module DebugFeedback
    TYPES = %w[visual content broken idea question].freeze

    # Structural validation of the report document. Deliberately
    # permissive about the INSIDE of target/environment/diagnostics:
    # dry-schema ignores unknown keys, so a client that learns to send a
    # new field does not start failing against an endpoint that has not
    # been taught about it yet.
    ReportSchema = Dry::Schema.JSON do
        required(:schema).value(:integer, included_in?: [1])
        required(:type).value(:string, included_in?: DebugFeedback::TYPES)

        required(:page).hash do
            required(:url).filled(:string, max_size?: 2048)
            optional(:title).maybe(:string)
            optional(:site).maybe(:string)
            optional(:build).maybe(:string)
        end

        optional(:message).maybe(:string, max_size?: 8192)
        optional(:target).value(:hash)
        optional(:environment).value(:hash)
        optional(:diagnostics).value(:hash)
        optional(:capture).value(:hash)
    end

    # Returns the document unchanged, so the stored report is verbatim.
    def self.validate(document)
        result = ReportSchema.call(document)
        raise PayloadError, result.errors.to_h.inspect unless result.success?

        document
    end
end
