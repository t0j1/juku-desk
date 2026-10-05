require "test_helper"

class WordbooksControllerTest < ActionDispatch::IntegrationTest
  def csv_upload(text)
    Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: "list.csv")
  end

  test "only admins can open the upload screen" do
    sign_in_as users(:staff)
    get wordbooks_path
    assert_redirected_to root_path
  end

  test "admin uploads a CSV" do
    sign_in_as users(:system_admin)
    assert_difference "Wordbook.count", 1 do
      post wordbooks_path, params: { name: "追加単語帳", file: csv_upload("No,単語,意味\n1,a,あ\n") }
    end
    assert_redirected_to wordbooks_path
  end

  test "duplicate numbers show an error and keep the data" do
    sign_in_as users(:system_admin)
    post wordbooks_path, params: { name: wordbooks(:leap).name, file: csv_upload("No,単語,意味\n1,changed,変更\n") }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /すでに登録/
    assert_equal "word1", words(:leap_1).reload.term
  end

  test "overwrite replaces the word" do
    sign_in_as users(:system_admin)
    post wordbooks_path, params: { name: wordbooks(:leap).name, overwrite: "1", file: csv_upload("No,単語,意味\n1,changed,変更\n") }
    assert_redirected_to wordbooks_path
    assert_equal "changed", words(:leap_1).reload.term
  end
end
