require "test_helper"

class ProgressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:staff)
    sign_in_as @user
    @progress = JobProgress.create!(user: @user, kind: "dummy", title: "ダミー処理", status: :running, total: 4, done: 1, started_at: 10.seconds.ago)
  end

  test "show returns json" do
    get progress_path(@progress), as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal 25, body["percent"]
    assert_equal "running", body["status"]
    assert_equal false, body["finished"]
  end

  test "index lists active and recently finished, not other users or old ones" do
    JobProgress.create!(user: users(:system_admin), kind: "dummy", title: "他人", status: :running)
    JobProgress.create!(user: @user, kind: "dummy", title: "古い", status: :succeeded, finished_at: 1.hour.ago)
    get progresses_path, as: :json
    assert_equal [ @progress.id ], response.parsed_body["progresses"].map { |p| p["id"] }
  end

  test "other users progress is not found" do
    other = JobProgress.create!(user: users(:system_admin), kind: "dummy", title: "他人", status: :running)
    get progress_path(other), as: :json
    assert_response :not_found
    post cancel_progress_path(other), as: :json
    assert_response :not_found
    assert_nil other.reload.cancel_requested_at
  end

  test "cancel records the request on a running job" do
    post cancel_progress_path(@progress), as: :json
    assert_response :success
    assert @progress.reload.cancel_requested?
    assert @progress.running?
    assert_equal true, response.parsed_body["cancel_requested"]
  end

  test "requires login" do
    sign_out
    get progresses_path, as: :json
    assert_response :redirect
  end

  test "show and index report a stalled running job as failed" do
    @progress.update_columns(updated_at: 10.minutes.ago)
    get progress_path(@progress), as: :json
    assert_equal "failed", response.parsed_body["status"]
    assert_equal true, response.parsed_body["finished"]
  end
end
