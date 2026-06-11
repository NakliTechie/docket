require "test_helper"

# Guards the locale files against the bug class behind H8: a duplicate
# YAML key (e.g. two `admin:` mappings) is silently kept-last by Psych,
# dropping the entire other subtree with no error.
class I18nLocalesTest < ActiveSupport::TestCase
  LOCALE_FILES = Dir[Rails.root.join("config/locales/*.yml")].freeze

  test "no locale file has duplicate keys (Psych would silently drop one)" do
    LOCALE_FILES.each do |file|
      assert_no_duplicate_keys(YAML.parse_file(file).root, file, [])
    end
  end

  test "admin.users translations resolve in every locale" do
    %i[en hi].each do |loc|
      assert_not_equal "MISSING",
        I18n.t("admin.users.fields.name", locale: loc, default: "MISSING"),
        "admin.users.fields.name missing in #{loc} (duplicate admin: key regression)"
    end
  end

  test "every LLM provider has a label in every locale (guards the unquoted off: key)" do
    %i[en hi].each do |loc|
      Llm::PROVIDERS.each do |provider|
        assert_not_equal "MISSING",
          I18n.t("admin.settings.show.providers.#{provider}", locale: loc, default: "MISSING"),
          "provider label '#{provider}' missing in #{loc}"
      end
    end
  end

  test "en and hi declare the same translation keys" do
    en = flatten_keys(YAML.load_file(Rails.root.join("config/locales/en.yml"))["en"])
    hi = flatten_keys(YAML.load_file(Rails.root.join("config/locales/hi.yml"))["hi"])
    assert_equal [], (en - hi).sort, "keys present in en.yml but missing from hi.yml"
    assert_equal [], (hi - en).sort, "keys present in hi.yml but missing from en.yml"
  end

  private

  def assert_no_duplicate_keys(node, file, path)
    return unless node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map { |k, _| k.respond_to?(:value) ? k.value : nil }.compact
    dups = keys.tally.select { |_, n| n > 1 }.keys
    assert dups.empty?, "#{File.basename(file)}: duplicate keys #{dups.inspect} under '#{path.join(".")}'"
    node.children.each_slice(2) do |k, v|
      assert_no_duplicate_keys(v, file, path + [ k.respond_to?(:value) ? k.value : "?" ])
    end
  end

  def flatten_keys(hash, prefix = "")
    hash.flat_map do |k, v|
      key = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
      v.is_a?(Hash) ? flatten_keys(v, key) : [ key ]
    end
  end
end
