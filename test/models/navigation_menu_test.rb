require "test_helper"

class NavigationMenuTest < ActiveSupport::TestCase
  def menu(controller_path: "students", action_name: "index", env: {})
    NavigationMenu.build(controller_path:, action_name:, env:)
  end

  def active_labels(groups) = groups.flat_map(&:items).select(&:active).map(&:label)

  test "without SCHEDULE_WEB_URL the schedule group only has the juku-desk daily schedule" do
    groups = menu
    assert_equal [ "塾日報ステーション", "スケジュール" ], groups.map(&:label)
    assert_equal %w[生徒データベース PDF分割 印刷 小テスト作成 マーキング検出], groups.first.items.map(&:label)
    assert_equal [ "1日のスケジュール" ], groups.last.items.map(&:label)
  end

  test "a blank or invalid SCHEDULE_WEB_URL hides the embedded schedule pages" do
    [ "", "  ", "javascript:alert(1)", "not a url", "ftp://example.com" ].each do |value|
      assert_equal [ "1日のスケジュール" ], menu(env: { "SCHEDULE_WEB_URL" => value }).last.items.map(&:label), value.inspect
    end
  end

  test "the schedule group links to the embedded pages inside juku-desk" do
    groups = menu(env: { "SCHEDULE_WEB_URL" => "https://sekigaku.example.pages.dev/" })
    assert_equal [ "塾日報ステーション", "スケジュール" ], groups.map(&:label)
    items = groups.last.items
    assert_equal %w[1日のスケジュール 年間スケジュール 管理画面 生徒ページ], items.map(&:label)
    assert_equal %w[/schedule/daily /schedule /schedule/admin /schedule/pickup], items.map(&:href)
    assert items.none?(&:external)
  end

  test "the embedded page is highlighted in the schedule group" do
    env = { "SCHEDULE_WEB_URL" => "https://sekigaku.example.pages.dev" }
    { "index" => "年間スケジュール", "admin" => "管理画面", "pickup" => "生徒ページ" }.each do |action, label|
      assert_equal [ label ], active_labels(menu(controller_path: "schedule", action_name: action, env:))
    end
  end

  test "the daily schedule is highlighted" do
    assert_equal [ "1日のスケジュール" ], active_labels(menu(controller_path: "daily_schedule"))
  end

  test "the current screen is highlighted" do
    assert_equal [ "生徒データベース" ], active_labels(menu(controller_path: "students"))
    assert_equal [ "PDF分割" ], active_labels(menu(controller_path: "tools/pdf_splitter/jobs", action_name: "show"))
    assert_equal [ "印刷" ], active_labels(menu(controller_path: "tools/pdf_splitter/jobs", action_name: "print"))
    assert_equal [ "印刷" ], active_labels(menu(controller_path: "print_library"))
    assert_equal [ "小テスト作成" ], active_labels(menu(controller_path: "quizzes", action_name: "new"))
    assert_empty active_labels(menu(controller_path: "home"))
  end

  test "every route named in config/navigation.yml exists" do
    YAML.safe_load_file(NavigationMenu::CONFIG_PATH, symbolize_names: true)[:groups].flat_map { |g| g[:items] }.filter_map { |i| i[:route] }.each do |route|
      assert_nothing_raised { Rails.application.routes.url_helpers.public_send("#{route}_path") }
    end
  end
end
