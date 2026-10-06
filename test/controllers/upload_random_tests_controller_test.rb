require "test_helper"

class UploadRandomTestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    @regions = make_regions(3, status: :extracted)
    @upload = @regions.first.upload
    @regions.each_with_index { |r, i| 2.times { |j| make_q(r, "問#{i}-#{j}") } }
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def make_q(region, text, **attrs)
    region.questions.create!({ subject: "英語", question_text: text, answer_text: "答え", reviewed_at: Time.current }.merge(attrs))
  end

  def picked_ids = css_select("#picked-questions li").map { |li| li["data-question"].to_i }

  test "the upload page offers a random-create form with default 5" do
    get upload_path(@upload)
    assert_select "#random-test-form input[name=count][value='5']"
  end

  test "preview picks N distinct approved questions of this image only" do
    make_q(@regions.first, "未承認", reviewed_at: nil)
    other = make_regions(1, status: :extracted).first
    make_q(other, "別の画像")
    get new_upload_random_test_path(@upload, count: 4)
    assert_response :success
    ids = picked_ids
    assert_equal 4, ids.size
    assert_equal ids.uniq, ids
    assert_empty ids - Question.approved.where(region_id: @upload.crop_regions.select(:id)).ids
    assert_select "#shortfall", false
  end

  test "N above the total uses the total and says so" do
    get new_upload_random_test_path(@upload, count: 20)
    assert_equal 6, picked_ids.size
    assert_select "#shortfall", /足りないため 6 問/
  end

  test "re-rolling can change the result" do
    results = 12.times.map { get(new_upload_random_test_path(@upload, count: 2)); picked_ids.sort }.uniq
    assert_operator results.size, :>, 1
    get new_upload_random_test_path(@upload, count: 2)
    assert_select "a#reroll[href=?]", new_upload_random_test_path(@upload, count: 2)
  end

  test "create builds the test from exactly the previewed questions, ignoring other images and unapproved ones" do
    other = make_regions(1, status: :extracted).first
    foreign = make_q(other, "別の画像")
    mine = @upload.crop_regions.first.questions.first
    assert_difference -> { Exam.count } => 1 do
      post upload_random_test_path(@upload), params: { title: "ランダム", count: 3, question_ids: [ mine.id, foreign.id ] }
    end
    test = Exam.last
    assert_redirected_to marking_test_path(test)
    assert_equal [ mine.id ], test.items.map(&:question_id)
  end

  test "create with no valid questions does not make a test" do
    assert_no_difference -> { Exam.count } do
      post upload_random_test_path(@upload), params: { title: "x", count: 3, question_ids: [] }
    end
    assert_redirected_to new_upload_random_test_path(@upload, count: 3)
  end

  test "viewers cannot use it" do
    sign_out
    sign_in_as users(:viewer) if users(:viewer) rescue skip("no viewer fixture")
    get new_upload_random_test_path(@upload)
    assert_redirected_to uploads_path
  end
end
