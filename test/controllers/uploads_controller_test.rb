require "test_helper"

class UploadsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:staff)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store") # テストごとの保存先（並列実行でも混ざらない）
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  # サーバーは画像をデコードしないので、先頭のマジックナンバーだけ本物の JPEG にしたダミーで足りる
  def jpeg(name, body = name)
    path = File.join(@dir, name)
    File.binwrite(path, "\xFF\xD8\xFF\xE0".b + body.b)
    Rack::Test::UploadedFile.new(path, "image/jpeg")
  end

  def payload(image: jpeg("page.jpg"), regions: 2)
    {
      image: image, width: 800, height: 600,
      regions: regions.times.to_h do |i|
        [ i.to_s, { bbox: { x: 10 * i, y: 20, w: 100, h: 50, angle: 0, manual: i == 1 }.to_json,
                    confidence: (i == 1 ? nil : 0.93), image: jpeg("crop#{i}.jpg") } ]
      end
    }
  end

  test "requires login" do
    sign_out
    post uploads_path, params: payload
    assert_redirected_to new_session_path
  end

  test "saves the upload and its confirmed regions, and audits it" do
    assert_difference [ "Upload.count" ], 1 do
      assert_difference "CropRegion.count", 2 do
        post uploads_path, params: payload
      end
    end
    assert_response :created
    upload = Upload.last
    assert_equal [ 800, 600, "image/jpeg", users(:staff).id ], [ upload.width, upload.height, upload.content_type, upload.user_id ]
    assert_match(/\Amarking\/uploads\/\h{64}\.jpg\z/, upload.r2_key)
    regions = upload.crop_regions.order(:id)
    assert_equal %w[confirmed confirmed], regions.map(&:status)
    assert_equal 0.93, regions.first.confidence
    assert_nil regions.last.confidence
    assert_equal({ "x" => 10, "y" => 20, "w" => 100, "h" => 50, "angle" => 0, "manual" => true }, regions.last.bbox)
    assert File.exist?(ImageStorage.disk_path(upload.r2_key))
    assert File.exist?(ImageStorage.disk_path(regions.first.r2_key))
    assert_equal "create", AuditLog.last.action
  end

  test "with GEMINI_API_KEY the confirmed regions are queued for structuring and the request returns right away" do
    with_gemini(gemini_json)
    assert_enqueued_jobs 1, only: Marking::StructureJob do # 2 領域を 1 つのジョブで順に処理する
      post uploads_path, params: payload
    end
    assert_response :created
    assert_equal %w[queued queued], Upload.last.crop_regions.order(:id).map(&:status)
  ensure
    reset_gemini
  end

  test "the same image uploaded twice stays one upload" do
    post uploads_path, params: payload
    assert_response :created
    assert_no_difference [ "Upload.count", "CropRegion.count" ] do
      post uploads_path, params: payload(regions: 1)
    end
    assert_response :success
    body = response.parsed_body
    assert_equal true, body["duplicate"]
    assert_equal Upload.last.id, body["id"]
    assert_equal 2, body["regions"]
  end

  test "rejects a file that is not JPEG or PNG" do
    path = File.join(@dir, "evil.jpg")
    File.write(path, "<html>not an image</html>")
    assert_no_difference "Upload.count" do
      post uploads_path, params: payload(image: Rack::Test::UploadedFile.new(path, "image/jpeg"))
    end
    assert_response :unsupported_media_type
  end

  test "rejects a file over the size limit (MARKING_MAX_BYTES)" do
    ENV["MARKING_MAX_BYTES"] = "100"
    assert_no_difference "Upload.count" do
      post uploads_path, params: payload(image: jpeg("big.jpg", "x" * 500))
    end
    assert_response :content_too_large
  ensure
    ENV.delete("MARKING_MAX_BYTES")
  end

  test "a region with a broken bbox saves nothing" do
    params = payload
    params[:regions]["0"][:bbox] = "{not json"
    assert_no_difference [ "Upload.count", "CropRegion.count" ] do
      post uploads_path, params: params
    end
    assert_response :unprocessable_entity
    assert_not Dir.exist?(ImageStorage.disk_root.join("marking"))
  end

  test "viewer can look but not upload" do
    sign_in_as users(:viewer)
    get uploads_path
    assert_response :success
    get new_upload_path
    assert_redirected_to uploads_path
    assert_no_difference "Upload.count" do
      post uploads_path, params: payload
    end
    assert_response :forbidden
  end

  test "index, show and the image endpoints work" do
    post uploads_path, params: payload
    upload = Upload.last
    get uploads_path
    assert_response :success
    assert_select "#upload_#{upload.id}"
    get upload_path(upload)
    assert_response :success
    assert_select "[data-region-box]", 2
    get image_upload_path(upload)
    assert_equal "image/jpeg", response.media_type
    get image_crop_region_path(upload.crop_regions.first)
    assert_response :success
  end

  test "a model_unavailable region shows its own message and 構造化を開始・やり直す re-queues it; several questions per region are listed" do
    post uploads_path, params: payload
    upload = Upload.last
    unavailable, extracted = upload.crop_regions.order(:id)
    unavailable.update!(status: :model_unavailable, error_message: CropRegion::MODEL_UNAVAILABLE_MESSAGE)
    extracted.update!(status: :extracted)
    extracted.questions.create!(source_label: "〔1〕", question_text: "問一", answer_text: "答")
    extracted.questions.create!(source_label: "〔2〕", question_text: "問二", answer_text: "答")

    get upload_path(upload)
    assert_select "#extraction-status", /モデルが利用できません/
    assert_select "#region_#{unavailable.id}", /モデルが利用できません：GEMINI_MODELを更新してください/
    assert_select "#region_#{extracted.id} [data-question]", 2
    get questions_path
    assert_select "#model-unavailable", /GEMINI_MODELを更新してください（1 件）/

    ENV["GEMINI_API_KEY"] = "test-key"
    assert_enqueued_jobs 1, only: Marking::StructureJob do
      post extract_upload_path(upload)
    end
    assert_equal "queued", unavailable.reload.status
  ensure
    ENV.delete("GEMINI_API_KEY")
  end

  test "new page hands the detector thresholds to the browser from the environment" do
    ENV["MARKING_MIN_AREA_RATIO"] = "0.02"
    get new_upload_path
    config = JSON.parse(css_select("[data-controller=marking]").first["data-marking-config-value"])
    assert_equal 0.02, config.dig("detector", "minAreaRatio")
    assert_equal 1600, config["maxLongSide"]
  ensure
    ENV.delete("MARKING_MIN_AREA_RATIO")
  end
end
