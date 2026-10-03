require "test_helper"

class PdfSplitter::PrintQueueTest < ActiveSupport::TestCase
  setup do
    @job = create_pdf_job(fixture: "scanned_images.pdf")
    [ [ "第1回", "problem", 2, 4 ], [ "第2回", "problem", 5, 7 ], [ "第1回", "answer", 8, 9 ], [ "第2回", "answer", 10, 12 ] ].each_with_index do |(r, k, f, t), i|
      @job.outputs.create!(display_name: "#{r}_#{k}", round_label: r, section_kind: k, page_from: f, page_to: t, position: i)
    end
  end

  def pages(pdf) = PdfSplitter::Splitter.page_count_of(pdf)

  test "problem only / answer only / both for one round" do
    assert_equal [ [ 2, 4 ] ], PdfSplitter::PrintQueue.new(@job, [ "第1回:problem" ]).ranges
    assert_equal [ [ 8, 9 ] ], PdfSplitter::PrintQueue.new(@job, [ "第1回:answer" ]).ranges
    q = PdfSplitter::PrintQueue.new(@job, [ "第1回:both" ])
    assert_equal [ [ 2, 4 ], [ 8, 9 ] ], q.ranges
    assert_equal 5, pages(q.to_pdf)
  end

  test "queue keeps the user's order across rounds" do
    q = PdfSplitter::PrintQueue.new(@job, [ "第2回:both", "第1回:problem" ])
    assert_equal [ [ 5, 7 ], [ 10, 12 ], [ 2, 4 ] ], q.ranges
    assert_equal 9, pages(q.to_pdf)
    assert_equal "第2回問題と解答_第1回問題のみ.pdf", q.filename
  end

  test "pad_even adds a blank page after each odd-length part" do
    q = PdfSplitter::PrintQueue.new(@job, [ "第1回:both" ], pad_even: true) # 3 pages + 2 pages
    assert_equal 6, pages(q.to_pdf)
  end

  test "limits the number of rounds and rejects empty or unknown items" do
    assert_not PdfSplitter::PrintQueue.new(@job, []).valid?
    assert_not PdfSplitter::PrintQueue.new(@job, [ "第9回:both" ]).valid?
    assert_not PdfSplitter::PrintQueue.new(@job, [ "第1回:../../etc" ]).valid?
    over = (1..5).map { |i| "第#{i}回:both" }
    q = PdfSplitter::PrintQueue.new(@job, over)
    assert_not q.valid?
    assert_includes q.errors.join, "4回分まで"
  end
end
