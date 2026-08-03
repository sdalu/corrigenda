# frozen_string_literal: true

require_relative "lib/corrigenda/api"
require_relative "lib/corrigenda/home"
require_relative "lib/corrigenda/intake"
require_relative "lib/corrigenda/prefix"
require_relative "lib/corrigenda/review"

# Before the maps: Rack::URLMap appends its own segment to SCRIPT_NAME,
# so the outer prefix has to be in place first.
use Corrigenda::Prefix

map("/report") { run Corrigenda::Intake }
map("/review") { run Corrigenda::Review }

# Mounted whether or not the deployment wants it: the app itself answers
# 404 to everything when the config says nothing about `api:`, so there is
# one place that decides rather than two that must agree.
map("/api")    { run Corrigenda::API }

map("/")       { run Corrigenda::Home }
