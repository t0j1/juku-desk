require "test_helper"

class StudentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:instructor) }

  test "requires login" do
    sign_out
    get students_path
    assert_redirected_to new_session_path
  end

  test "index is audited as view and filters by weekday" do
    assert_difference -> { AuditLog.where(action: "view").count }, 1 do
      get students_path(weekday: 4)
    end
    assert_response :success
    assert_select "#students td", text: students(:taro).name
    assert_select "#students td", text: students(:mika).name, count: 0
  end

  test "show is audited with the student" do
    get student_path(students(:taro))
    assert_response :success
    assert_equal students(:taro), AuditLog.last.auditable
    assert_equal users(:instructor), AuditLog.last.user
  end

  test "instructor registers a student with weekdays and it is audited" do
    assert_difference [ "Student.count", -> { AuditLog.where(action: "create").count } ], 1 do
      post students_path, params: { student: { name: "鈴木 一郎", grade: "中1", weekdays: [ "", "2", "5" ] } }
    end
    student = Student.order(:id).last
    assert_redirected_to student
    assert_equal [ 2, 5 ], student.weekdays
    assert_equal({ "weekdays" => [ 2, 5 ] }, AuditLog.last.metadata)
  end

  test "invalid create re-renders" do
    post students_path, params: { student: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "update replaces weekdays and is audited" do
    s = students(:taro)
    patch student_path(s), params: { student: { grade: "中3", lock_version: s.lock_version, weekdays: [ "", "3" ] } }
    assert_redirected_to s
    assert_equal [ 3 ], s.reload.weekdays
    assert_equal "update", AuditLog.last.action
  end

  test "stale update returns conflict" do
    s = students(:taro)
    stale = s.lock_version
    s.update!(note: "先に更新")
    patch student_path(s), params: { student: { note: "後から", lock_version: stale } }
    assert_response :conflict
    assert_equal "先に更新", s.reload.note
  end

  test "weekday add and remove are audited" do
    s = students(:mika)
    assert_difference -> { s.student_weekdays.count }, 1 do
      post student_student_weekdays_path(s), params: { student_weekday: { weekday: 6 } }
    end
    w = s.student_weekdays.find_by(weekday: 6)
    assert_difference -> { s.student_weekdays.count }, -1 do
      delete student_student_weekday_path(s, w)
    end
    assert_equal 2, AuditLog.where(auditable: s, action: "update").count
  end

  test "instructor cannot delete" do
    assert_no_difference "Student.count" do
      delete student_path(students(:taro))
    end
    assert_redirected_to root_path
  end

  test "manager can delete and it is audited" do
    sign_in_as users(:manager)
    assert_difference "Student.count", -1 do
      delete student_path(students(:mika))
    end
    assert_equal "delete", AuditLog.last.action
  end

  test "deactivated user is locked out on next request" do
    get students_path
    assert_response :success
    users(:instructor).update!(active: false)
    get students_path
    assert_redirected_to new_session_path
  end

  test "stale lock_version is rejected even when only weekdays change" do
    student = students(:taro)
    stale = student.lock_version
    student.update!(note: "他の人が更新")
    patch student_path(student), params: { student: { lock_version: stale, weekdays: [ "1" ] } }
    assert_response :conflict
  end
end
