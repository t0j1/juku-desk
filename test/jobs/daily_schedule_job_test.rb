require "test_helper"

class DailyScheduleJobTest < ActiveJob::TestCase
  setup do
    @task = DailyScheduleTask.create!(name: "日報", execution_time: "18:00", repeat_type: "daily", execution_type: "create_draft",
                                      template_key: "daily_report", save_destination: "drafts")
    @task.update_columns(created_at: Time.zone.local(2026, 10, 5))
  end

  test "runs the tasks whose time has come, once" do
    now = Time.zone.local(2026, 10, 5, 18, 1)

    assert_equal({ "draft_saved" => 1 }, DailyScheduleJob.perform_now(now))
    assert_equal({}, DailyScheduleJob.perform_now(now + 1.minute))
    assert_equal 1, @task.executions.count
  end

  test "does nothing before the time and for disabled tasks" do
    assert_equal({}, DailyScheduleJob.perform_now(Time.zone.local(2026, 10, 5, 17, 59)))
    @task.update!(enabled: false)
    assert_equal({}, DailyScheduleJob.perform_now(Time.zone.local(2026, 10, 5, 18, 1)))
    assert_equal 0, DailyScheduleExecution.count
  end

  test "a slot missed by more than the grace period is recorded as not run, never executed late" do
    result = DailyScheduleJob.perform_now(Time.zone.local(2026, 10, 5, 19, 0))

    assert_equal({ "not_run" => 1 }, result)
    assert_equal "not_run", @task.executions.last.status
  end

  test "a task created after the planned time is not counted as missed" do
    @task.update_columns(created_at: Time.zone.local(2026, 10, 5, 18, 30))
    assert_equal({}, DailyScheduleJob.perform_now(Time.zone.local(2026, 10, 5, 19, 0)))
  end
end
