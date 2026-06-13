# Parse a user-entered money amount into integer cents (L8). Uses BigDecimal so
# half-cent inputs round exactly (no binary-float drift), and returns nil for a
# blank/unparseable amount — never a false 0 from String#to_f swallowing garbage.
module Cents
  module_function

  def from(amount)
    return nil if amount.blank?
    (BigDecimal(amount.to_s.strip) * 100).round
  rescue ArgumentError
    nil
  end
end
