# 承認済みの問題から小テストを作って、問題用・解答用の印刷画面（HTML + 印刷用 CSS。PDF はブラウザで保存）を出す。
class MarkingTestsController < ApplicationController
  before_action :set_test, only: %i[ show print ]

  def index
    @tests = Exam.includes(:items).order(id: :desc).limit(50)
  end

  def new
    @builder = Marking::TestBuilder.new
    @approved_count = Question.approved.count
  end

  def create
    @builder = Marking::TestBuilder.new(builder_params)
    if @builder.save(current_user)
      AuditLog.record!(:create, @builder.test, metadata: { count: @builder.test.items.size })
      redirect_to marking_test_path(@builder.test), status: :see_other
    else
      @approved_count = Question.approved.count
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @items = @test.items.includes(:question)
  end

  # kind=question（問題用）/ answer（解答用）
  def print
    @kind = params[:kind] == "answer" ? :answer : :question
    @items = @test.items.includes(:question)
    AuditLog.record!(:print, @test, metadata: { kind: @kind })
    render layout: "application"
  end

  private
    def set_test
      @test = Exam.find(params[:id])
    end

    def builder_params
      params.require(:marking_test).permit(:title, :mode, :count, :subject, :tags_text, :tag_logic, :difficulty_min, :difficulty_max)
    end
end
