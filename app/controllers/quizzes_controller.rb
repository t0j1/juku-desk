class QuizzesController < ApplicationController
  before_action :set_wordbook, only: %i[ new create ]

  # 1: 単語帳を選ぶ（wordbook_id なし） / 2: 範囲と問題数（wordbook_id あり）
  def new
    @wordbooks = Wordbook.order(:name)
    return unless @wordbook

    # 開始No. は毎回 1、語数は 100 から始める（前回の続きは自動で入れない）。
    # 「範囲を変更」で戻ってきたときだけ、プレビューの入力値を初期値にする
    @quiz = Quiz.defaults_for(@wordbook)
    @quiz.count = nil # 最初は問題数を選んでいない状態から始める（あいさつの吹き出しが「何問いってみる？」と聞く）
    @quiz.end_no = nil
    @quiz.span = Quiz::DEFAULT_SPAN
    given = params.permit(:start_no, :end_no, :span, :count)
    @quiz.assign_attributes(given)
    if given[:span].blank? && @quiz.start_no && @quiz.end_no && @quiz.end_no >= @quiz.start_no
      @quiz.span = @quiz.end_no - @quiz.start_no + 1
    end
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
      params.expect(quiz: %i[ start_no end_no span count ])
    end
end
