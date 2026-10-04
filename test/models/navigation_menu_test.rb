require "test_helper"

class NavigationMenuTest < ActiveSupport::TestCase
  def menu(controller_path: "students", action_name: "index", env: {})
    NavigationMenu.build(controller_path:, action_name:, env:)
  end

  def active_labels(groups) = groups.flat_map(&:items).select(&:active).map(&:label)

  test "without SCHEDULE_WEB_URL only the juku-desk group is shown" do
    groups = menu
    assert_equal [ "塾日報ステーション" ], groups.map(&:label)
    assert_equal %w[生徒データベース PDF分割 印刷 小テスト作成], groups.first.items.map(&:label)
  end

  test "a blank or invalid SCHEDULE_WEB_URL hides the group too" do
    [ "", "  ", "javascript:alert(1)", "not a url", "ftp://example.com" ].each do |value|
      assert_equal 1, menu(env: { "SCHEDULE_WEB_URL" => value }).size, value.inspect
    end
  end

  test "schedule-web links are built from SCHEDULE_WEB_URL and are not marked active" do
    groups = menu(env: { "SCHEDULE_WEB_URL" => "https://sekigaku.example.pages.dev/" })
    assert_equal [ "塾日報ステーション", "スケジュール" ], groups.map(&:label)
    items = groups.last.items
    assert_equal %w[年間スケジュール 管理画面 生徒ページ], items.map(&:label)
    assert_equal %w[https://sekigaku.example.pages.dev/index.html https://sekigaku.example.pages.dev/admin.html https://sekigaku.example.pages.dev/pickup.html], items.map(&:href)
    assert items.all?(&:external)
    assert items.none?(&:active)
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
