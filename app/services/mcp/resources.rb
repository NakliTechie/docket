module Mcp
  module Resources
    ENTRIES = [
      {
        "uri" => "docket://workflows",
        "name" => "Docket governed workflows",
        "description" => "The six packaged operating workflows and their intended controls.",
        "mimeType" => "text/markdown"
      },
      {
        "uri" => "docket://operator-guide",
        "name" => "Docket operator guide",
        "description" => "Operational configuration, security, backup, and decisioning guidance.",
        "mimeType" => "text/markdown"
      },
      {
        "uri" => "docket://openapi",
        "name" => "Docket API contract",
        "description" => "The tenant-filtered OpenAPI document behind the MCP tool catalogue.",
        "mimeType" => "application/json"
      }
    ].freeze

    module_function

    def list
      ENTRIES
    end

    def read(uri)
      content = content_for(uri)
      entry = ENTRIES.find { |candidate| candidate["uri"] == uri.to_s }
      {
        "contents" => [
          { "uri" => entry.fetch("uri"), "mimeType" => entry.fetch("mimeType"), "text" => content }
        ]
      }
    end

    def filtered_openapi
      document = Docket::Openapi.document.deep_dup
      paths = document[:paths] || document["paths"]
      paths&.select! { |path, _| Features.api_path_enabled?(path) }
      document
    end
    private_class_method :filtered_openapi

    def content_for(uri)
      case uri.to_s
      when "docket://workflows" then Mcp::Workflows.markdown
      when "docket://operator-guide" then Rails.root.join("docs/OPERATOR-GUIDE.md").read
      when "docket://openapi" then JSON.pretty_generate(filtered_openapi)
      else raise Mcp::Error.new(-32602, "unknown resource: #{uri}")
      end
    end
    private_class_method :content_for
  end
end
