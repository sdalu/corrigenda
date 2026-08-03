# frozen_string_literal: true

require_relative "lib/corrigenda/home"
require_relative "lib/corrigenda/intake"
require_relative "lib/corrigenda/prefix"
require_relative "lib/corrigenda/review"

# Before the maps: Rack::URLMap appends its own segment to SCRIPT_NAME,
# so the outer prefix has to be in place first.
use Corrigenda::Prefix

map("/report") { run Corrigenda::Intake }
map("/review") { run Corrigenda::Review }
map("/")       { run Corrigenda::Home }
