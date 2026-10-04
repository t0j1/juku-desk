require "test_helper"

class SectionTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "index shows the defaults from the sample layout" do
    sign_in_as users(:staff)
    get section_templates_path
    assert_response :success
    assert_select "#section_template_reorder", /次の（ ）内の語を並べ替えて，英文を完成させなさい。/
    assert_select "#section_template_passage", /次の文章を読んで，後の問いに答えなさい。/
    assert_select "#section_template_translate_en_ja", /次の文を訳しなさい。/
    assert_select "#section_template_compose_ja_en", /日本語に合うように，英文を書きなさい。/
  end

  test "staff and system_admin can edit and reset; edits are audited" do
    [ users(:staff), users(:system_admin) ].each do |u|
      sign_in_as u
      assert_difference -> { AuditLog.where(action: "section_template_update").count }, 1 do
        patch section_template_path("reorder"), params: { section_template: { instruction: "並べ替えなさい（#{u.role}）。" } }
      end
      assert_redirected_to section_templates_path
      assert_equal "並べ替えなさい（#{u.role}）。", SectionTemplate.instructions["reorder"]
      post reset_section_template_path("reorder")
      assert_equal SectionTemplate::DEFAULTS["reorder"], SectionTemplate.instructions["reorder"]
    end
  end

  test "viewer cannot edit; blank and unknown types are rejected" do
    sign_in_as users(:viewer)
    patch section_template_path("reorder"), params: { section_template: { instruction: "x" } }
    assert_response :forbidden
    assert_equal 0, SectionTemplate.count

    sign_in_as users(:staff)
    patch section_template_path("reorder"), params: { section_template: { instruction: " " } }
    assert_response :unprocessable_entity
    get edit_section_template_path("bogus")
    assert_response :not_found
  end
end
