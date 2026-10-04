require "test_helper"

# 英語の問題形式（question_type / payload）と、解答の出どころ（answer_source）。Gemini はモック。
class Marking::QuestionTypesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
  end

  teardown do
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  PAYLOADS = {
    "reorder" => { "ja" => "その計画はうまくいっている。", "words" => %w[trying well is worth], "prefix" => "The plan", "suffix" => ".", "extra_count" => 1 },
    "translate_en_ja" => { "source" => "I have lived here for ten years." },
    "compose_ja_en" => { "ja" => "私は昨日公園へ行った。", "template" => "I ___ to the park ___.", "blank_count" => 2 },
    "passage" => { "body" => "Tom <u>(ア) went</u> to school.", "sub_questions" => [ { "prompt" => "下線部(ア)を訳せ。", "answer" => "行った" } ] },
    "fill_blank" => { "body" => "I ___ a student.", "blank_count" => 1 }
  }.freeze

  test "each English question type keeps its payload; unknown keys are dropped" do
    items = PAYLOADS.map { |type, payload| { "question_type" => type, "payload" => payload.merge("junk" => "x"), "answer_in_material" => true } }
    with_gemini(gemini_questions_json(*items))
    region = make_regions(1).first
    Marking::Extractor.call(region)

    assert_equal "extracted", region.reload.status
    saved = region.questions.to_h { |q| [ q.question_type, q.payload ] }
    assert_equal PAYLOADS, saved
    assert_equal [ "material" ], region.questions.map(&:answer_source).uniq
  end

  test "English without a recognisable type becomes free; non-English has no type or payload" do
    with_gemini(gemini_questions_json({ "question_type" => "essay" }, { "question_type" => nil }, { "subject" => "数学", "question_type" => "reorder", "payload" => PAYLOADS["reorder"] }))
    region = make_regions(1).first
    Marking::Extractor.call(region)
    english1, english2, math = region.reload.questions
    assert_equal [ "free", "free", nil ], [ english1.question_type, english2.question_type, math.question_type ]
    assert_equal({}, math.payload)
  end

  test "an answer the AI wrote is marked ai, and it is not quiz material until approved" do
    with_gemini(gemini_json("answer_in_material" => false, "question_type" => "translate_en_ja", "payload" => PAYLOADS["translate_en_ja"]))
    region = make_regions(1).first
    Marking::Extractor.call(region)
    question = region.reload.questions.sole
    assert_equal [ "ai", "am" ], [ question.answer_source, question.answer_text ]
    assert question.ai_answer?

    picker = Marking::QuestionPicker.new(Marking::QuestionPicker::Params.new(mode: "random", count: 10, tags: [], tag_logic: "or"))
    assert_empty picker.pick
    question.approve!(users(:staff))
    assert_equal [ question.id ], picker.pick.map(&:id)
  end

  test "with answer generation off, an answer missing from the material stays empty and the region needs review" do
    with_gemini(gemini_json("answer_in_material" => false), gemini_json("answer_in_material" => true))
    off, kept = make_regions(2)
    [ off, kept ].each { |r| r.update!(generate_answers: false) }
    Marking::Extractor.call(off)
    Marking::Extractor.call(kept)

    assert_equal "needs_review", off.reload.status
    assert_equal [ "", "material" ], [ off.questions.sole.answer_text, off.questions.sole.answer_source ]
    refute off.questions.sole.approvable?
    assert_equal [ "extracted", "am" ], [ kept.reload.status, kept.questions.sole.answer_text ] # 教材にある解答は使う
  end

  test "the prompt and the schema follow the answer setting" do
    with_gemini(gemini_json)
    prompts = []
    fake = Object.new
    fake.define_singleton_method(:generate) { |_img, mime_type:, prompt:| prompts << prompt; GeminiTestHelper::VALID.to_json }
    Marking::Extractor.client = fake
    a, b = make_regions(2)
    b.update!(generate_answers: false)
    Marking::Extractor.call(a)
    Marking::Extractor.call(b)
    assert_equal [ Gemini::Prompt::TEXT, Gemini::Prompt::TEXT_WITHOUT_ANSWERS ], prompts
    assert_includes Gemini::Schema::QUESTION[:properties].keys, :question_type
    assert_includes Gemini::Schema::QUESTION[:properties].keys, :payload
    assert_equal Question::TYPES, Gemini::Schema::QUESTION[:properties][:question_type][:enum]
  end

  test "the enqueuer stores the choice and a resume keeps it" do
    ENV["GEMINI_API_KEY"] = "test-key"
    region = make_regions(1, status: :confirmed).first
    Marking::Enqueuer.call(CropRegion.where(id: region.id), generate_answers: false)
    refute region.reload.generate_answers
    region.update!(status: :quota_exceeded)
    Marking::ResumeJob.perform_now
    assert_equal [ "queued", false ], [ region.reload.status, region.generate_answers ]
  end
end
