require "test_helper"

class StudentTest < ActiveSupport::TestCase
  test "attending_on returns only students of that weekday" do
    assert_equal [ students(:mika), students(:taro) ].sort, Student.attending_on(1).to_a.sort
    assert_equal [ students(:taro) ], Student.attending_on(4).to_a
    assert_empty Student.attending_on(0)
  end

  test "weekday must be 0..6 and unique per student" do
    assert_not students(:taro).student_weekdays.build(weekday: 7).valid?
    assert_not students(:taro).student_weekdays.build(weekday: 1).valid?
  end

  test "optimistic locking" do
    a = Student.find(students(:taro).id)
    b = Student.find(students(:taro).id)
    a.update!(note: "A")
    assert_raises(ActiveRecord::StaleObjectError) { b.update!(note: "B") }
  end
end
