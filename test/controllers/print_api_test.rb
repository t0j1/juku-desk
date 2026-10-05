require "test_helper"

class PrintApiTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  setup do
    @station, @token = PrintStation.register!(name: "教室A")
    @auth = { "Authorization" => "Bearer #{@token}" }
  end

  def make_job(station: @station, **attrs)
    PrintJob.create_with_pdf!(station: station, title: "小テスト", data: PDF_BYTES, driver_preset: "A4両面・左上ホチキス", staple: "左上", copies: 3, **attrs)
  end

  test "every endpoint needs a valid, unrevoked token" do
    post "/api/v1/print/heartbeat"
    assert_response :unauthorized
    get "/api/v1/print/jobs/next", headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
    @station.revoke!
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :unauthorized
  end

  test "reissuing invalidates the old token" do
    new_token = @station.reissue_token!
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :unauthorized
    get "/api/v1/print/jobs/next", headers: { "Authorization" => "Bearer #{new_token}" }
    assert_response :no_content
  end

  test "only the digest of the token is stored" do
    assert_not_equal @token, @station.token_digest
    assert_equal PrintStation.digest(@token), @station.token_digest
  end

  test "heartbeat returns server_time, records the station, and only offers an update when fully configured" do
    post "/api/v1/print/heartbeat", params: { agent_version: "0.1.0" }, headers: @auth, as: :json
    assert_response :success
    body = response.parsed_body
    assert_in_delta Time.current.to_i, Time.iso8601(body["server_time"]).to_i, 5
    assert_not body.key?("latest_version")
    assert_equal "0.1.0", @station.reload.agent_version
    assert @station.online?

    with_env("PRINT_AGENT_LATEST_VERSION" => "0.2.0", "PRINT_AGENT_DOWNLOAD_URL" => "https://x/a.exe", "PRINT_AGENT_SHA256" => "ab" * 32) do
      post "/api/v1/print/heartbeat", headers: @auth, as: :json
      assert_equal({ "latest_version" => "0.2.0", "download_url" => "https://x/a.exe", "sha256" => "ab" * 32 }, response.parsed_body.slice("latest_version", "download_url", "sha256"))
    end
    with_env("PRINT_AGENT_LATEST_VERSION" => "0.2.0") do
      post "/api/v1/print/heartbeat", headers: @auth, as: :json
      assert_not response.parsed_body.key?("latest_version")
    end
  end

  test "heartbeat stores toner/paper status, and unknown or missing values become nil" do
    post "/api/v1/print/heartbeat", params: { toner_status: "low", paper_status: "empty" }, headers: @auth, as: :json
    assert_equal %w[low empty], @station.reload.then { [ it.toner_status, it.paper_status ] }
    post "/api/v1/print/heartbeat", params: { toner_status: "unknown", paper_status: nil }, headers: @auth, as: :json
    assert_equal [ nil, nil ], @station.reload.then { [ it.toner_status, it.paper_status ] }
  end

  test "job json carries duplex (nil when unset)" do
    assert_nil make_job.as_agent_json(base_url: "http://x")[:duplex]
    assert_equal "long", make_job(duplex: "long").as_agent_json(base_url: "http://x")[:duplex]
    assert_not make_job(duplex: "").tap { |j| j.reload }.duplex
  end

  test "next leases a due job with the agent's fields and the file url downloads the pdf" do
    job = make_job(scheduled_at: 1.minute.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :success
    j = response.parsed_body["job"]
    assert_equal job.id.to_s, j["id"]
    assert_equal [ 3, true, "A4両面・左上ホチキス", "左上" ], j.values_at("copies", "collate", "driver_preset", "staple")
    assert_equal Digest::SHA256.hexdigest(PDF_BYTES), j["sha256"]
    assert_in_delta (Time.current + 15.minutes).to_i, Time.iso8601(j["lease_until"]).to_i, 5
    assert_equal (job.scheduled_at + 2.hours).to_i, Time.iso8601(j["expires_at"]).to_i
    assert job.reload.leased?

    get j["file_url"].sub("http://www.example.com", "")
    assert_response :success
    assert_equal PDF_BYTES, response.body.b
  end

  test "next gives nothing for a future job, another station's job, or while leased" do
    make_job(scheduled_at: 1.hour.from_now)
    make_job(station: PrintStation.register!(name: "教室B").first, scheduled_at: 1.minute.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :no_content

    make_job(scheduled_at: 1.minute.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :success
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :no_content
  end

  test "a lease that is not reported before lease_until is redelivered" do
    job = make_job(scheduled_at: 1.minute.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    travel 16.minutes do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :success
      assert_equal job.id.to_s, response.parsed_body.dig("job", "id")
      assert_equal 2, job.reload.lease_count
    end
  end

  test "jobs past expires_at are never handed out and show as expired" do
    job = make_job(scheduled_at: 3.hours.ago, expires_at: 1.hour.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    assert_response :no_content
    assert job.reload.expired?
    assert_match "締め切り", job.result_message
  end

  test "an expired lease past the deadline is expired, not redelivered" do
    job = make_job(scheduled_at: 1.minute.ago, expires_at: 20.minutes.from_now)
    get "/api/v1/print/jobs/next", headers: @auth
    travel 21.minutes do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :no_content
      assert job.reload.expired?
    end
  end

  test "result spooled acknowledges; reporting again is accepted; unknown status is rejected" do
    job = make_job(scheduled_at: 1.minute.ago)
    get "/api/v1/print/jobs/next", headers: @auth
    post "/api/v1/print/jobs/#{job.id}/result", params: { status: "spooled" }, headers: @auth, as: :json
    assert_equal({ "accepted" => true }, response.parsed_body)
    assert job.reload.acknowledged?
    assert_nil job.lease_until
    post "/api/v1/print/jobs/#{job.id}/result", params: { status: "spooled" }, headers: @auth, as: :json
    assert_equal true, response.parsed_body["accepted"]
    post "/api/v1/print/jobs/#{job.id}/result", params: { status: "failed" }, headers: @auth, as: :json
    assert_equal false, response.parsed_body["accepted"]
    assert job.reload.acknowledged?
    post "/api/v1/print/jobs/#{job.id}/result", params: { status: "printed" }, headers: @auth, as: :json
    assert_response :unprocessable_entity
  end

  test "result failed and expired are recorded with the message" do
    a = make_job(scheduled_at: 1.minute.ago)
    b = make_job(scheduled_at: 1.minute.ago)
    post "/api/v1/print/jobs/#{a.id}/result", params: { status: "failed", message: "用紙切れ" }, headers: @auth, as: :json
    post "/api/v1/print/jobs/#{b.id}/result", params: { status: "expired" }, headers: @auth, as: :json
    assert a.reload.failed?
    assert_equal "用紙切れ", a.result_message
    assert b.reload.expired?
  end

  test "a cancelled job accepts a late report without changing" do
    job = make_job(scheduled_at: 1.minute.ago)
    job.cancel!
    post "/api/v1/print/jobs/#{job.id}/result", params: { status: "spooled" }, headers: @auth, as: :json
    assert_equal true, response.parsed_body["accepted"]
    assert job.reload.cancelled?
  end

  test "another station's job is not found" do
    other = make_job(station: PrintStation.register!(name: "教室B").first)
    get "/api/v1/print/jobs/#{other.id}", headers: @auth
    assert_response :not_found
    post "/api/v1/print/jobs/#{other.id}/result", params: { status: "spooled" }, headers: @auth, as: :json
    assert_response :not_found
  end

  test "show returns a fresh file url" do
    job = make_job
    get "/api/v1/print/jobs/#{job.id}", headers: @auth
    assert_match %r{/api/v1/print/files/}, response.parsed_body.dig("job", "file_url")
  end

  test "the db file url expires after 10 minutes and a tampered one is refused" do
    job = make_job(scheduled_at: 1.minute.ago)
    url = job.file_url(base_url: "")
    get url
    assert_response :success
    get url + "x"
    assert_response :not_found
    travel 11.minutes do
      get url
      assert_response :not_found
    end
  end

  test "in r2 mode the file url is a presigned url valid for 10 minutes and nothing is stored in the db" do
    with_pdf_storage("r2") do |r2|
      job = make_job(scheduled_at: 1.minute.ago)
      assert_nil job.pdf_data
      assert_equal [ job.r2_key ], r2.objects.keys
      assert_match %r{\Aprint/}, job.r2_key
      get "/api/v1/print/jobs/#{job.id}", headers: @auth
      assert_equal "https://r2.example.test/#{job.r2_key}?expires=600", response.parsed_body.dig("job", "file_url")
    end
  end

  test "a non-pdf or oversized upload is refused" do
    assert_raises(ArgumentError) { PrintJob.create_with_pdf!(station: @station, title: "x", data: "not a pdf") }
  end

  private
    def with_env(vars)
      old = vars.keys.to_h { |k| [ k, ENV[k] ] }
      vars.each { |k, v| ENV[k] = v }
      yield
    ensure
      old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
end
