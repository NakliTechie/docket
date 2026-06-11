# Connector framework (Phase 0). A provider knows how to FETCH raw records
# from one external system; the Sync engine maps them through the
# connector's field mapping and upserts them into a Docket entity, logging
# a ConnectorRun. Every connector in plan/connectors-roadmap.md is a new
# Provider subclass registered in Connectors::Registry.
module Connectors
  class Error < StandardError; end
end
