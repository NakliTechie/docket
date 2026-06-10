# human_<attr> label methods for enum columns, backed by i18n
# (e.g. cases.enum.status.in_progress) so en/hi both render.
module HumanEnums
  extend ActiveSupport::Concern

  class_methods do
    def humanizes_enums(*attrs)
      attrs.each do |attr|
        define_method("human_#{attr}") do
          value = public_send(attr)
          value.nil? ? "" : I18n.t("#{model_name.collection}.enum.#{attr}.#{value}")
        end
      end
    end
  end
end
