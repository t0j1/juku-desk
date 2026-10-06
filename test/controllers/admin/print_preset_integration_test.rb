require "test_helper"

class AdminPrintPresetIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    sign_in_as @admin
    @station = print_stations(:one)
  end

  test "test_print with new preset via dropdown creates preset and uses it" do
    post test_print_admin_print_station_path(@station), params: {
      test_print: { driver_preset: "__new__", driver_preset: "新しいテストプリセット", staple: "左上", sheets: 2, duplex: "long" }
    }
    assert_response :redirect
    follow_redirect!
    assert_match "テスト印刷のジョブを作りました", response.body

    job = @station.test_print_job
    assert_equal "新しいテストプリセット", job.driver_preset
    assert PrintPreset.exists?(name: "新しいテストプリセット")
  end

  test "test_print with existing preset uses it" do
    PrintPreset.create!(name: "既存プリセット")

    post test_print_admin_print_station_path(@station), params: {
      test_print: { driver_preset: "既存プリセット", staple: "左上", sheets: 2, duplex: "long" }
    }
    assert_response :redirect

    job = @station.test_print_job
    assert_equal "既存プリセット", job.driver_preset
  end

  test "test_print with unknown preset name directly (not via __new__) is rejected" do
    post test_print_admin_print_station_path(@station), params: {
      test_print: { driver_preset: "存在しないプリセット", staple: "左上", sheets: 2, duplex: "long" }
    }
    assert_response :redirect
    follow_redirect!
    assert_match "登録されていません", response.body
  end

  test "print_job create with new preset via dropdown" do
    output = pdf_split_outputs(:one)

    post admin_print_jobs_path, params: {
      print_job: { output_id: output.id, print_station_id: @station.id, driver_preset: "__new__", driver_preset: "ジョブ用プリセット", copies: 2 }
    }
    assert_response :redirect
    follow_redirect!
    assert_match "印刷ジョブを作りました", response.body

    job = PrintJob.last
    assert_equal "ジョブ用プリセット", job.driver_preset
    assert PrintPreset.exists?(name: "ジョブ用プリセット")
  end

  test "print_job create rejects unknown preset name" do
    output = pdf_split_outputs(:one)

    post admin_print_jobs_path, params: {
      print_job: { output_id: output.id, print_station_id: @station.id, driver_preset: "存在しないプリセット", copies: 2 }
    }
    assert_response :unprocessable_entity
    assert_match "登録されていません", response.body
  end

  test "print_schedule create with new preset" do
    PrintSchedule.delete_all

    post admin_print_schedules_path, params: {
      print_schedule: {
        name: "新スケジュール",
        kind: "fixed_pdf",
        print_station_id: @station.id,
        copies: 1,
        time_of_day: "08:00",
        weekdays: [1],
        driver_preset: "__new__",
        driver_preset: "スケジュール用プリセット",
        pdf: fixture_file_upload("test.pdf", "application/pdf")
      }
    }
    assert_response :redirect

    schedule = PrintSchedule.last
    assert_equal "スケジュール用プリセット", schedule.driver_preset
    assert PrintPreset.exists?(name: "スケジュール用プリセット")
  end

  test "daily_schedule_task create with new preset" do
    post daily_schedule_tasks_path, params: {
      daily_schedule_task: {
        name: "テストタスク",
        execution_time: "09:00",
        repeat_type: "daily",
        execution_type: "print",
        print_station_id: @station.id,
        copies: 1,
        driver_preset: "__new__",
        driver_preset: "デイリープリセット",
        pdf: fixture_file_upload("test.pdf", "application/pdf")
      },
      date: Date.current.iso8601
    }
    assert_response :redirect

    task = DailyScheduleTask.last
    assert_equal "デイリープリセット", task.driver_preset
    assert PrintPreset.exists?(name: "デイリープリセット")
  end

  test "marking_test print_job with new preset" do
    exam = exams(:one)

    post print_job_marking_test_path(exam), params: {
      print_job: {
        print_station_id: @station.id,
        copies: 1,
        driver_preset: "__new__",
        driver_preset: "マーキングプリセット",
        staple: "左上",
        collate: "1"
      },
      kind: "question"
    }
    assert_response :redirect
    follow_redirect!
    assert_match "印刷ジョブを作りました", response.body

    job = PrintJob.last
    assert_equal "マーキングプリセット", job.driver_preset
    assert PrintPreset.exists?(name: "マーキングプリセット")
  end

  test "edit views show existing value as '現在の値' when not in preset list" do
    # 既存ジョブが一覧にないプリセット名を持っている状況を作る
    job = PrintJob.create_with_pdf!(
      station: @station,
      title: "テストジョブ",
      data: "%PDF-1.4\n%test",
      driver_preset: "古いプリセット名",
      copies: 1
    )

    # print_schedule edit でも同様
    schedule = PrintSchedule.create!(
      name: "編集テスト",
      print_station: @station,
      copies: 1,
      time_of_day: "08:00",
      weekdays: [1],
      driver_preset: "古いスケジュールプリセット",
      kind: "fixed_pdf",
      sha256: "abc",
      byte_size: 100
    )

    get edit_admin_print_schedule_path(schedule)
    assert_response :success
    # current_value が含まれることを確認（HTML に「現在の値」が出る）
    assert_match "古いスケジュールプリセット", response.body
    assert_match "現在の値", response.body
  end

  test "daily_schedule edit shows existing value as 現在の値" do
    task = DailyScheduleTask.create!(
      name: "編集タスク",
      execution_time: "10:00",
      repeat_type: "daily",
      execution_type: "print",
      print_station: @station,
      copies: 1,
      driver_preset: "古いデイリープリセット",
      sha256: "abc",
      byte_size: 100,
      created_by: @admin
    )

    get daily_schedule_path_for(Date.current, task: task.id)
    assert_response :success
    assert_match "古いデイリープリセット", response.body
    assert_match "現在の値", response.body
  end
end
