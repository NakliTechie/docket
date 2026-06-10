module Llm
  # OpenAI-compatible /chat/completions over plain Net::HTTP. The only
  # outbound network call Docket ever makes besides configured mail.
  class HttpClient
    attr_reader :endpoint, :model

    def initialize(endpoint:, model:, api_key: nil)
      @endpoint = endpoint.chomp("/")
      @api_key = api_key
      @model = model
    end

    # messages: [{ role:, content: }]. Returns assistant content string.
    # json: true asks for a JSON object response and parses it.
    def chat(messages, json: false, temperature: 0.2, max_tokens: 1024)
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      body[:response_format] = { type: "json_object" } if json

      response = post_json("#{endpoint}/chat/completions", body)
      content = response.dig("choices", 0, "message", "content")
      raise Error, "empty completion" if content.blank?
      json ? parse_json(content) : content
    end

    private

    def post_json(url, payload)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 120

      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = JSON.generate(payload)
      response = http.request(request)
      raise Error, "LLM endpoint returned #{response.code}" unless response.code.to_i == 200
      JSON.parse(response.body)
    rescue JSON::ParserError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Error, "LLM request failed: #{e.class}: #{e.message}"
    end

    def headers
      base = { "Content-Type" => "application/json" }
      base["Authorization"] = "Bearer #{@api_key}" if @api_key
      base
    end

    def parse_json(content)
      JSON.parse(content.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, ""))
    rescue JSON::ParserError => e
      raise Error, "LLM returned invalid JSON: #{e.message}"
    end
  end
end
