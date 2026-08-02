require "test_helper"

class Audioproxy::Rails::RailtieTest < ActiveSupport::TestCase
  test "the dummy app boots with the gem's railtie registered" do
    assert ::Rails.application.initialized?
    assert_includes ::Rails.application.railties.map(&:class), Audioproxy::Rails::Railtie
  end
end
