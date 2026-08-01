module Notifications
  module Mentions
    BRACKETED = /@\[([^\]]+)\]/
    EMAIL = /(?<![\w@])@([a-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,})/i

    module_function

    def users_in(body)
      tokens = body.to_s.scan(BRACKETED).flatten + body.to_s.scan(EMAIL).flatten
      return User.none if tokens.empty?

      normalized = tokens.map { |token| token.strip.downcase }.uniq
      User.active.where("LOWER(email_address) IN (?) OR LOWER(name) IN (?)", normalized, normalized)
    end
  end
end
