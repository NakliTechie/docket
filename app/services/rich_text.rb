module RichText
  module_function

  # A deliberately small Markdown subset for customer replies. Input is escaped
  # first, then only known tags are introduced; Rails sanitizes the result again.
  def render(text)
    markup = ERB::Util.html_escape(text.to_s)
    markup.gsub!(/`([^`\n]+)`/, '<code>\1</code>')
    markup.gsub!(/\*\*([^*\n]+)\*\*/, '<strong>\1</strong>')
    markup.gsub!(/_([^_\n]+)_/, '<em>\1</em>')
    markup.gsub!(%r{\[([^\]\n]+)\]\((https?://[^\s)]+)\)}) do
      %(<a href="#{Regexp.last_match(2)}" rel="nofollow noopener">#{Regexp.last_match(1)}</a>)
    end
    ActionController::Base.helpers.simple_format(markup, {}, sanitize: true)
  end
end
