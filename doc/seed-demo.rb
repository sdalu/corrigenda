#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Fill a THROWAWAY store with plausible reports, for the screenshots in
# README.md. Everything here is example.com: a picture of a review list
# is published, and a real hostname in one is a leak no test can catch
# because no test reads an image.
#
#   ruby doc/seed-demo.rb /var/tmp/corrigenda-doc-store
#   ./run -f -p 9399 -d /var/tmp/corrigenda-doc-store
#
# Then drive a headless browser at it, which is where the pictures come
# from and what the rest of this note is for:
#
#   doc/widget.png   the fixture page, a visual report with figcaption
#                    picked and the screenshot switch off (nothing here
#                    can answer a screen-share prompt), clipped to the
#                    panel's own box plus 12px, viewport 900x820.
#   doc/review.png   /.corrigenda/review/ at 1500x760, clipped to main.
#
# Both at deviceScaleFactor 2, and both with /common/fonts/* fulfilled
# from /web/platform/Common/fonts -- a fixture run serves no /common/,
# and without them the pages fall back to a serif no deployment shows.
# The widget asks for `system-ui`, which a headless machine may not
# have either; naming a real sans in the shadow root for the shot is
# the difference between a picture of the widget and a picture of
# Chromium's last resort.

require_relative "../lib/corrigenda"

store = Corrigenda::Store.new(ARGV.fetch(0))

REPORTS = [
    { type: "visual", site: "www.example.com",
      url: "https://www.example.com/press/",
      message: "The caption sits on top of the photograph below 700px.",
      capture: %w[fragment rules computed diagnostics audit screenshot],
      state: "proposed", by: "claude" },

    { type: "content", site: "www.example.com",
      url: "https://www.example.com/about/",
      message: "« Nous somme ouverts » — one s missing, second paragraph.",
      capture: %w[fragment], state: "fixed" },

    { type: "broken", site: "gallery.example.com",
      url: "https://gallery.example.com/2019/venice/",
      message: "The lightbox never opens; the console says two scripts " \
               "failed to load.",
      capture: %w[fragment diagnostics screenshot], state: "open" },

    { type: "idea", site: "www.example.com",
      url: "https://www.example.com/press/",
      message: "Could each entry carry its date?",
      capture: [], state: "open" },

    { type: "visual", site: "gallery.example.com",
      url: "https://gallery.example.com/prints/",
      message: "Grey on grey: the price fails contrast against the card.",
      capture: %w[fragment rules computed audit screenshot],
      state: "open" }
]

CHANNELS = %w[fragment rules computed diagnostics audit screenshot].freeze

REPORTS.each do |report|
    document = {
        "schema"  => 1,
        "type"    => report[:type],
        "page"    => { "url" => report[:url], "site" => report[:site],
                       "title" => "example.com" },
        "message" => report[:message],
        "capture" => CHANNELS.to_h { [it, report[:capture].include?(it)] }
    }

    id = store.save(document, reporter: "alice")
    store.mark(id, report[:state], by: report[:by] ? nil : "alice",
                                   agent: report[:by])
end

puts "seeded #{REPORTS.size} reports into #{ARGV.fetch(0)}"
