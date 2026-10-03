class QuizzesController < ApplicationController
  before_action :set_wordbook, only: %i[ new create ]

  # 1: 単語帳を選ぶ（wordbook_id なし） / 2: 範囲と問題数（wordbook_id あり）
  def new
    @wordbooks = Wordbook.order(:name)
    return unless @wordbook

    # 「範囲を変更」で戻ってきたときは、前回の入力値を初期値にする
    @quiz = Quiz.defaults_for(@wordbook)
    @quiz.assign_attributes(params.permit(:start_no, :end_no, :count))
  end

  # 検証して抽選し、印刷プレビュー（3）を出す。「問題を入れ替える」も同じ条件でここへ送る
  def create
    return redirect_to(new_quiz_path, status: :see_other) unless @wordbook

    @quiz = Quiz.new(quiz_params.merge(wordbook: @wordbook))
    if @quiz.valid?
      @words = @quiz.draw
      @left, @right = Quiz.split(@words.size)
      AuditLog.record!(:create, @wordbook, metadata: { quiz: { start_no: @quiz.start_no, end_no: @quiz.end_no, count: @quiz.count } })
      render :preview
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_wordbook
      id = params.dig(:quiz, :wordbook_id) || params[:wordbook_id]
      @wordbook = Wordbook.find_by(id: id)
    end

    def quiz_params
      params.expect(quiz: %i[ start_no end_no count ])
    end
end
