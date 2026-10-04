require "test_helper"
require "zip"

# 出力PDF（ダウンロード・印刷・ZIP・まとめ）は、保存されているバイト列と一致して返る。String に載せず、ファイルから流して返す
class PdfOutputStreamingTest < ActionDispatch::IntegrationTest
  setup do
    skip "qpdf が必要です" unless system("which qpdf", out: File::NULL, err: File::NULL)
    sign_in_as users(:staff)
    @job = create_pdf_job
    @job.update!(status: :done)
    @outputs = [ [ "第1回_問題", 1, 3, "problem" ], [ "第1回_解答", 4, 5, "answer" ] ].each_with_index.map do |(name, from, to, kind), i|
      @job.outputs.create!(display_name: name, page_from: from, page_to: to, round_label: "第1回", section_kind: kind, position: i)
    end
    @job.with_original_file { |path| @outputs.each { |o| PdfSplitter::Builder.ensure_stored(o, source_path: path) } }
  end

  def stored_bytes(output) = output.pdf_blobs.first.read

  test "download and print return exactly the stored bytes with the same headers as before" do
    @outputs.each do |o|
      get download_tools_pdf_splitter_job_output_path(@job, o)
      assert_response :success
      assert_equal stored_bytes(o), response.body.b
      assert_equal "application/pdf", response.media_type
      assert_match(/attachment/, response.headers["Content-Disposition"])
      assert_equal stored_bytes(o).bytesize.to_s, response.headers["Content-Length"]

      get print_tools_pdf_splitter_job_output_path(@job, o)
      assert_equal stored_bytes(o), response.body.b
      assert_match(/inline/, response.headers["Content-Disposition"])
    end
  end

  test "an output that was not stored is regenerated and returned with the same bytes the builder stores" do
    o = @outputs.first
    o.pdf_blobs.destroy_all
    get download_tools_pdf_splitter_job_output_path(@job, o)
    assert_response :success
    assert_equal stored_bytes(o.reload), response.body.b
  end

  test "zip contains each output byte for byte" do
    get download_zip_tools_pdf_splitter_job_path(@job)
    assert_response :success
    assert_equal "application/zip", response.media_type
    entries = {}
    Zip::InputStream.open(StringIO.new(response.body)) do |zis|
      while (entry = zis.get_next_entry)
        entries[entry.name.dup.force_encoding("UTF-8")] = zis.read
      end
    end
    assert_equal @outputs.map(&:filename).sort, entries.keys.sort
    @outputs.each { |o| assert_equal stored_bytes(o), entries.fetch(o.filename).b }
  end

  test "bundle equals combining the stored outputs" do
    freeze_time do # CombinePDF は作成時刻（秒）をメタデータに入れる
      expected = CombinePDF.new.tap { |pdf| @outputs.each { |o| pdf << CombinePDF.parse(stored_bytes(o)) } }.to_pdf
      get print_bundle_tools_pdf_splitter_job_path(@job, round: "第1回")
      assert_response :success
      assert_equal expected.b, response.body.b
    end
  end

  test "print queue returns a valid PDF with the selected pages" do
    get print_queue_tools_pdf_splitter_job_path(@job, items: [ "第1回:both" ])
    assert_response :success
    assert_equal 5, PDF::Reader.new(StringIO.new(response.body)).page_count
  end

  test "print link downloads match too" do
    sign_out
    link = PrintLink.reissue!(by: users(:system_admin))
    o = @outputs.first
    get kiosk_job_output_download_path(token: link.token, job_id: @job, id: o)
    assert_equal stored_bytes(o), response.body.b
    get kiosk_job_output_print_path(token: link.token, job_id: @job, id: o)
    assert_equal stored_bytes(o), response.body.b
  end

  test "the same bytes are returned from R2 storage" do
    with_pdf_storage("r2") do |r2|
      job = create_r2_job
      o = job.outputs.first
      stored = o.pdf_blobs.first
      get download_tools_pdf_splitter_job_output_path(job, o)
      assert_response :success
      assert_equal r2.objects.fetch(stored.r2_key), response.body.b
    end
  end

  private
    def create_r2_job
      data = file_fixture("workbook_p1.pdf").binread
      job = users(:staff).pdf_split_jobs.create!(original_filename: "r2.pdf", page_count: PdfSplitter::Splitter.page_count_of(data), status: :done)
      PdfBlob.store!(kind: "original", pdf_split_job: job, data:, expires_at: 7.days.from_now)
      o = job.outputs.create!(display_name: "r2_out", page_from: 1, page_to: 2, round_label: "第1回", section_kind: "problem", position: 0)
      job.with_original_file { |path| PdfSplitter::Builder.ensure_stored(o, source_path: path) }
      job
    end
end
