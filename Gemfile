# -*- ruby -*-
#
# Corrigenda endpoint — see DESIGN.md
# Installed into vendor/ (see .bundle/config), as ops/Cfg does.

source "https://rubygems.org"

ruby ">= 3.4"

# Endpoint
gem "sinatra", "~> 4.2"
gem "puma",    "~> 8.0"
gem "rackup",  "~> 2.3"    # only Sinatra's classic `run!` needs this;
                           # production is `puma config.ru`

# Payload validation, at the boundary and nowhere else
gem "dry-schema", "~> 1.0"

# Tilt picks Erubi over stdlib ERB when it is present, and only Erubi
# honours Sinatra's escape_html — without it the review UI would render
# reported strings raw.
gem "erubi", "~> 1.13"

group :test do
    gem "minitest",  "~> 6.0"
    gem "rack-test", "~> 2.2"
    gem "rake",      "~> 13.0"
end
