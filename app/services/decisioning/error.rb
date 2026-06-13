module Decisioning
  # Raised on an invalid decision transition (e.g. approving one that isn't
  # awaiting confirmation, or releasing a decision of record without a reason).
  class Error < StandardError; end
end
