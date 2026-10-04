# 大問の指示文（問題形式ごと）を編集する。system_admin と staff（viewer は閲覧のみ）。
class SectionTemplatesController < ApplicationController
  before_action :set_template, only: %i[ edit update reset ]

  def index
    @templates = SectionTemplate.all_for_types
  end

  def edit
  end

  def update
    @template.assign_attributes(params.expect(section_template: [ :instruction ]).merge(updated_by: current_user))
    if @template.save
      AuditLog.record!(:section_template_update, @template, metadata: { question_type: @template.question_type })
      redirect_to section_templates_path, notice: "「#{@template.label}」の指示文を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def reset
    SectionTemplate.reset!(@template.question_type)
    AuditLog.record!(:section_template_reset, nil, metadata: { question_type: @template.question_type })
    redirect_to section_templates_path, notice: "「#{@template.label}」の指示文を初期値に戻しました。", status: :see_other
  end

  private
    def set_template
      raise ActiveRecord::RecordNotFound unless Question::TYPES.include?(params[:question_type])

      @template = SectionTemplate.for(params[:question_type])
    end
end
