# config/navigation.yml からサイドバーの中身を組み立てる。
class NavigationMenu
  Item = Struct.new(:label, :href, :icon, :active, :external, keyword_init: true)
  Group = Struct.new(:label, :items, keyword_init: true)

  CONFIG_PATH = Rails.root.join("config/navigation.yml")

  # controller_path / action_name: 現在の画面（現在地の強調に使う）
  def self.build(controller_path:, action_name:, env: ENV, config: nil)
    new(controller_path:, action_name:, env:, config:).groups
  end

  def initialize(controller_path:, action_name:, env:, config: nil)
    @controller_path = controller_path.to_s
    @action_name = action_name.to_s
    @env = env
    @config = config || YAML.safe_load_file(CONFIG_PATH, symbolize_names: true)
  end

  def groups
    @config.fetch(:groups).filter_map do |group|
      base = nil
      if group[:env]
        base = schedule_base_url(group[:env]) or next # 未設定・不正なら、グループごと出さない
      end
      items = group.fetch(:items).map { |item| build_item(item, base) }
      Group.new(label: group.fetch(:label), items:)
    end
  end

  private
    def build_item(item, base)
      if item[:route]
        Item.new(label: item[:label], href: Rails.application.routes.url_helpers.public_send("#{item[:route]}_path"),
                 icon: item[:icon]&.to_sym, active: active?(item), external: false)
      else
        Item.new(label: item[:label], href: "#{base}#{item.fetch(:path)}", icon: item[:icon]&.to_sym, active: false, external: true)
      end
    end

    def active?(item)
      matches = Array(item[:controllers]).any? { |pattern| match?(pattern) }
      matches && Array(item[:except]).none? { |pattern| match?(pattern) }
    end

    # "controller" / "controller*"（前方一致）/ "controller#action"
    def match?(pattern)
      controller, action = pattern.split("#", 2)
      return false if action && action != @action_name
      controller.end_with?("*") ? @controller_path.start_with?(controller.delete_suffix("*")) : @controller_path == controller
    end

    # http(s) の URL だけ受け付ける。末尾の / は取る
    def schedule_base_url(name)
      value = @env[name].to_s.strip
      return if value.empty?
      uri = URI.parse(value)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      value.delete_suffix("/")
    rescue URI::InvalidURIError
      nil
    end
end
