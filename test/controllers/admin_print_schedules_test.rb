require "test_helper"

class AdminPrintSchedulesTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  setup do
    sign_in_as users(:system_admin)
    @station, = PrintStation.register!(name: "教室A")
  end

  def pdf_upload
    Rack::Test::UploadedFile.new(StringIO.new(PDF_BYTES), "application/pdf", original_filename: "weekly.pdf")
  end

  def register(**attrs)
    post admin_print_schedules_path, params: { print_schedule: { name: "週テスト", print_station_id: @station.id, copies: 2, weekdays: %w[ 1 3 ], time_of_day: "08:00", driver_preset: "A4両面", pdf: pdf_upload }.merge(attrs) }
  end

  test "only system_admin can use it" do
    sign_in_as users(:staff)
    get admin_print_schedules_path
    assert_redirected_to root_path
  end

  test "registers a template, audits it, and lists it" do
    assert_difference -> { PrintSchedule.count }, 1 do
      assert_difference -> { AuditLog.where(action: "print_schedule_create").count }, 1 do
        register
      end
    end
    assert_redirected_to admin_print_schedules_path
    follow_redirect!
    assert_select "#print_schedules", /週テスト.*月・水.*08:00/m
  end

  test "refuses a template without a PDF, weekdays, or a station" do
    assert_no_difference -> { PrintSchedule.count } do
      post admin_print_schedules_path, params: { print_schedule: { name: "x", print_station_id: @station.id, weekdays: %w[ 1 ], time_of_day: "08:00" } }
      assert_response :unprocessable_entity
      register(weekdays: [])
      assert_response :unprocessable_entity
      register(print_station_id: "")
      assert_response :unprocessable_entity
    end
  end

  test "stops, resumes and deletes" do
    register
    schedule = PrintSchedule.last
    post toggle_admin_print_schedule_path(schedule)
    assert_not schedule.reload.active
    post toggle_admin_print_schedule_path(schedule)
    assert schedule.reload.active
    assert_difference -> { PrintSchedule.count }, -1 do
      delete admin_print_schedule_path(schedule)
    end
  end

  test "the new form renders" do
    get new_admin_print_schedule_path
    assert_response :success
    assert_select "input[name='print_schedule[weekdays][]']", 7
  end
end
