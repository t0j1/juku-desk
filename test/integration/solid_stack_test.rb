require "test_helper"

class SolidStackTest < ActiveSupport::TestCase
  test "Solid Queue / Cache / Cable schemas are loadable" do
    assert defined?(SolidQueue::Job)
    assert defined?(SolidCache::Entry)
    assert defined?(SolidCable::Message)
  end
end
