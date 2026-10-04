require "test_helper"

class KioskPrintTest < ActionDispatch::IntegrationTest
  setup do
    @link = PrintLink.reissue!(by: users(:system_admin))
    @done = PdfSplitJob.create!(user: users(:staff), original_filename: "英語_共通テスト.pdf", status: :done, page_count: 4, output_count: 1)
    @done.outputs.create!(display_name: "第1回_問題", page_from: 1, page_to: 2, round_label: "第1回", section_kind: "problem")
    @failed = PdfSplitJob.create!(user: users(:staff), original_filename: "失敗.pdf", status: :failed, page_count: 2)
  end

  test "valid link shows only done files from the whole school without login" do
    get kiosk_print_path(token: @link.token)
    assert_response :success
    assert_select "#print-jobs li", 1
    assert_match "英語_共通テスト.pdf", response.body
    assert_no_match "失敗.pdf", response.body
    assert_select "aside", 0
    assert_no_match "ログアウト", response.body
  end

  test "search filters by filename and shows the no-match message" do
    get kiosk_print_path(token: @link.token, q: "数学")
    assert_select "#print-empty", text: /該当する教材はありません/
  end

  test "print page opens via link with token-scoped print URLs" do
    get kiosk_job_path(token: @link.token, id: @done)
    assert_response :success
    assert_match "教材一覧へ戻る", response.body
    assert_match kiosk_job_print_queue_path(token: @link.token, id: @done), response.body
    assert_no_match "分割画面", response.body
  end

  test "non-done job is not reachable via link" do
    get kiosk_job_path(token: @link.token, id: @failed)
    assert_redirected_to kiosk_print_path(token: @link.token)
  end

  test "missing or wrong token is sent to login, and admin pages stay closed" do
    get "/print/#{'x' * 32}"
    assert_redirected_to new_session_path
    get print_library_path
    assert_redirected_to new_session_path
    get students_path
    assert_redirected_to new_session_path
    get tools_pdf_splitter_jobs_path
    assert_redirected_to new_session_path
  end

  test "reissue revokes the old token" do
    old = @link.token
    sign_in_as users(:system_admin)
    post reissue_print_link_path
    assert_redirected_to print_library_path
    sign_out
    get kiosk_print_path(token: old)
    assert_redirected_to new_session_path
    get kiosk_print_path(token: PrintLink.current.token)
    assert_response :success
  end

  test "only admins can reissue" do
    sign_in_as users(:staff)
    assert_no_difference -> { PrintLink.count } do
      post reissue_print_link_path
    end
  end

  test "logged-in print page lists own done files and admin sees the link box" do
    sign_in_as users(:system_admin)
    get print_library_path
    assert_response :success
    assert_select "#print-link"
    assert_select "nav a[aria-current=page]", text: "印刷"
  end
end
