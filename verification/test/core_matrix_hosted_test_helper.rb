ENV["RAILS_ENV"] ||= "test"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require File.expand_path("../../core_matrix/test/test_helper", __dir__)
require "verification/hosted/core_matrix"
