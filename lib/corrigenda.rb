# frozen_string_literal: true

require_relative "corrigenda/config"
require_relative "corrigenda/schema"
require_relative "corrigenda/store"

# Collects reports about a rendered page: what was picked, what the
# browser looked like, what broke. See CORRIGENDA.md for the spec.
module Corrigenda
    class Error        < StandardError; end
    class PayloadError < Error; end
    class StorageError < Error; end
end
