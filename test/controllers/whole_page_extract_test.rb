require "test_helper"

# 赤枠が無い画像は、ページ全体を 1 領域にして構造化する（取り込み時・既存の領域 0 件の画像・フォルダ一括）
class WholePageExtractTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class PromptCapturingClient
    attr_reader :prompts
    def initialize(json) = (@json = json; @prompts = [])
    def generate(_image, mime_type:, prompt:, **) = (@prompts << prompt; @json)
  end

  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
  end

  teardown do
    reset_gemini
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def jpeg(name, body = name)
    path = File.join(@dir, name)
    File.binwrite(path, "\xFF\xD8\xFF\xE0".b + body.b)
    Rack::Test::UploadedFile.new(path, "image/jpeg")
  end

  def zero_region_upload(sha_seed = "a")
    upload = Upload.create!(user: users(:staff), sha256: sha_seed * 64, content_type: "image/jpeg", byte_size: 12, width: 800, height: 600, r2_key: Upload.object_key(sha_seed * 64, "image/jpeg"))
    path = File.join(@dir, "orig-#{sha_seed}.jpg")
    File.binwrite(path, "\xFF\xD8\xFF\xE0".b + "page")
    ImageStorage.put_file(upload.r2_key, path, content_type: "image/jpeg")
    upload
  end

  test "an image uploaded with no red frames becomes one whole-page region and is queued for structuring" do
    with_gemini(gemini_json)
    assert_difference [ "Upload.count", "CropRegion.count" ], 1 do
      assert_enqueued_jobs 1, only: Marking::StructureJob do
        post uploads_path, params: { image: jpeg("page.jpg"), width: 800, height: 600 }
      end
    end
    assert_response :created
    assert_equal 1, response.parsed_body["regions"]
    region = Upload.last.crop_regions.sole
    assert region.whole?
    assert_equal({ "x" => 0, "y" => 0, "w" => 800, "h" => 600, "angle" => 0, "manual" => false, "whole" => true }, region.bbox)
    assert_equal "queued", region.status
    assert File.exist?(ImageStorage.disk_path(region.r2_key))
    assert_equal true, AuditLog.last.metadata["whole_page"]
  end

  test "an image with red frames is saved as before (no whole-page region)" do
    post uploads_path, params: { image: jpeg("page.jpg"), width: 800, height: 600,
                                 regions: { "0" => { bbox: { x: 10, y: 20, w: 100, h: 50, angle: 0, manual: false }.to_json, confidence: 0.9, image: jpeg("c.jpg") } } }
    assert_not Upload.last.crop_regions.sole.whole?
  end

  test "the whole-page prompt tells Gemini to skip chapter headings and page numbers, the framed prompt does not" do
    whole = Gemini::Prompt.for(generate_answers: true, whole: true)
    assert_includes whole, "ページ全体"
    assert_includes whole, "章見出し"
    assert_not_includes Gemini::Prompt.for(generate_answers: true), "章見出し"
    client = PromptCapturingClient.new(gemini_json)
    with_gemini(gemini_json)
    Marking::Extractor.client = client
    upload = zero_region_upload
    region = upload.add_whole_region!
    region.update!(status: :queued)
    Marking::Extractor.call(region)
    assert_equal "extracted", region.reload.status
    assert_includes client.prompts.sole, "章見出し"
  end

  test "an existing upload with zero regions can be structured as a whole page, once" do
    with_gemini(gemini_json)
    upload = zero_region_upload
    get upload_path(upload)
    assert_select "form#extract-whole input[type=submit][value=ページ全体で構造化する]"
    assert_enqueued_jobs 1, only: Marking::StructureJob do
      post extract_whole_upload_path(upload)
    end
    assert_redirected_to upload_path(upload)
    assert upload.crop_regions.sole.whole?
    assert_equal "queued", upload.crop_regions.sole.status
    get upload_path(upload)
    assert_select "form#extract-whole", count: 0
    assert_no_difference "CropRegion.count" do
      post extract_whole_upload_path(upload)
    end
    assert_match "すでに領域", flash[:alert]
  end

  test "viewers cannot use it and do not see the button" do
    with_gemini(gemini_json)
    upload = zero_region_upload
    sign_in_as users(:viewer)
    get upload_path(upload)
    assert_select "form#extract-whole", count: 0
    assert_no_difference "CropRegion.count" do
      post extract_whole_upload_path(upload)
    end
    assert_response :forbidden
  end

  test "the folder button structures every zero-region image of the folder as a whole page" do
    with_gemini(gemini_json)
    folder = QuestionFolder.create!(name: "10月")
    empty_a, empty_b = zero_region_upload("a"), zero_region_upload("b")
    framed = make_regions(1, status: :confirmed).first.upload
    [ empty_a, empty_b, framed ].each { |u| folder.folder_uploads.create!(upload: u) }
    get question_folder_path(folder)
    assert_select "form#extract-whole", text: /2 枚/
    assert_difference "CropRegion.count", 2 do
      assert_enqueued_jobs 1, only: Marking::StructureJob do
        post extract_whole_question_folder_path(folder)
      end
    end
    assert_equal [ true, true ], [ empty_a, empty_b ].map { |u| u.crop_regions.sole.whole? }
    assert_equal 1, framed.crop_regions.count
    get question_folder_path(folder)
    assert_select "form#extract-whole", count: 0
  end
end
