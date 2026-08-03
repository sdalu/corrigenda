# frozen_string_literal: true

require_relative "corrigenda/config"
require_relative "corrigenda/schema"
require_relative "corrigenda/store"

# Collects reports about a rendered page: what was picked, what the
# browser looked like, what broke. See CORRIGENDA.md for the spec.
module Corrigenda
    # The service and the widget it serves, which are one thing: a page
    # carrying corrigenda.js is running code from this checkout, and a
    # report that arrives says which. The number is repeated in
    # client/corrigenda.js -- a static file cannot read a constant --
    # and test/version_test.rb refuses to let the two drift.
    #
    # The add-on has a version of its own: it is installed rather than
    # served, so a browser can be carrying any of them.
    VERSION = "0.1.0"

    class Error        < StandardError; end
    class PayloadError < Error; end
    class StorageError < Error; end
end
