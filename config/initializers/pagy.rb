# Out-of-range ?page= params (a hand-typed or stale-link page number past
# the last page) should land on the last page rather than raising
# Pagy::OverflowError → a 500. Applies to every paginated surface (console
# case list, portal my-cases, admin tables).
require "pagy/extras/overflow"
Pagy::DEFAULT[:overflow] = :last_page
