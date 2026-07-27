module Imports
  # An import RECONSTRUCTS history. It must not RE-ENACT it.
  #
  # Without this, importing a Freshdesk ticket with three replies sent three
  # "Update on your case" emails to the real customer — a cutover would mail the
  # customer's entire customer base. The same reasoning covers AI triage,
  # webhooks, sentiment analysis and connector delivery: every one of them is a
  # reaction to something happening NOW, and an import is not now.
  #
  # Thread-local rather than a global, so a background import cannot silence a
  # live request handling real traffic at the same time.
  module Mode
    KEY = :docket_import_in_progress

    module_function

    def running?
      Thread.current[KEY] == true
    end

    def run
      previous = Thread.current[KEY]
      Thread.current[KEY] = true
      yield
    ensure
      Thread.current[KEY] = previous
    end
  end
end
