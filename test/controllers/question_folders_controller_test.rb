require "test_helper"

class QuestionFoldersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    @img_a = make_regions(3, status: :extracted)
    @img_b = make_regions(2, status: :extracted)
    (@img_a + @img_b).each_with_index { |r, i| r.questions.create!(subject: "英語", question_text: "問#{i}", answer_text: "答え", reviewed_at: Time.current) }
    @upload_a = @img_a.first.upload
    @upload_b = @img_b.first.upload
    @folder = QuestionFolder.create!(name: "10月")
    [ @upload_a, @upload_b ].each { |u| @folder.folder_uploads.create!(upload: u) }
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def picked_origins = css_select("#picked-questions li a[data-origin]").map { |a| a["data-origin"].to_i }

  test "create, rename and list folders" do
    assert_difference -> { QuestionFolder.count } => 1 do
      post question_folders_path, params: { question_folder: { name: "新しいフォルダ" } }
    end
    folder = QuestionFolder.find_by!(name: "新しいフォルダ")
    assert_redirected_to question_folder_path(folder)
    patch question_folder_path(folder), params: { question_folder: { name: "改名" } }
    assert_equal "改名", folder.reload.name
    post question_folders_path, params: { question_folder: { name: "" } }
    assert_redirected_to question_folders_path
    get question_folders_path
    assert_select "#folders li", 2
  end

  test "an image can be in several folders, and can be added and removed" do
    other = QuestionFolder.create!(name: "別")
    post question_folder_uploads_path(other), params: { upload_id: @upload_a.id }
    post question_folder_uploads_path(@folder), params: { upload_id: @upload_a.id } # 二重に入れても 1 件
    assert_equal [ @upload_a.id ], other.reload.upload_ids
    assert_equal 2, @folder.reload.uploads.count
    assert_equal 2, @upload_a.question_folders.count
  end

  test "manual selection lists questions of every image in the folder with their origin" do
    get question_folder_path(@folder)
    assert_select "#manual-questions li", 5
    assert_select "#manual-questions a[data-origin='#{@upload_a.id}']", 3
    assert_select "#manual-questions a[data-origin='#{@upload_b.id}']", 2
    ids = Question.approved.pluck(:id).first(3)
    assert_difference -> { Exam.count } => 1 do
      post question_folder_random_test_path(@folder), params: { title: "手動", question_ids: ids }
    end
    assert_equal ids.sort, Exam.last.items.map(&:question_id).sort
  end

  test "random N=4 draws from both images; N above the total uses the total" do
    seen = 15.times.flat_map { get(new_question_folder_random_test_path(@folder, count: 4)); assert_equal 4, picked_origins.size; picked_origins }.uniq
    assert_equal [ @upload_a.id, @upload_b.id ].sort, seen.sort
    get new_question_folder_random_test_path(@folder, count: 9)
    assert_equal 5, picked_origins.size
    assert_select "#shortfall", /足りないため 5 問/
  end

  test "removing an image takes its questions out of the pool" do
    delete question_folder_upload_path(@folder, @upload_b)
    get new_question_folder_random_test_path(@folder, count: 5)
    assert_equal [ @upload_a.id ], picked_origins.uniq
    assert_equal 3, picked_origins.size
    post question_folder_random_test_path(@folder), params: { title: "x", question_ids: Question.where(region_id: @img_b.map(&:id)).ids }
    assert_redirected_to new_question_folder_random_test_path(@folder, count: 5)
  end

  test "deleting a folder keeps images and questions" do
    assert_no_difference [ -> { Upload.count }, -> { Question.count } ] do
      assert_difference -> { QuestionFolder.count } => -1, -> { QuestionFolderUpload.count } => -2 do
        delete question_folder_path(@folder)
      end
    end
    assert_redirected_to question_folders_path
  end

  test "the test page shows which image each question came from" do
    post question_folder_random_test_path(@folder), params: { title: "出所", question_ids: Question.approved.ids }
    follow_redirect!
    assert_select "[data-origin='#{@upload_a.id}']"
    assert_select "[data-origin='#{@upload_b.id}']"
  end
end
