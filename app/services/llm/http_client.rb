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

    # Default read timeout for background work (the triage/draft job). The
    # interactive assist path passes a shorter one so it can't pin a Puma
    # worker for the full window (M21).
    DEFAULT_READ_TIMEOUT = 120

    # messages: [{ role:, content: }]. Returns assistant content string.
    # json: true asks for a JSON object response and parses it.
    def chat(messages, json: false, temperature: 0.2, max_tokens: 1024, read_timeout: DEFAULT_READ_TIMEOUT)
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      body[:response_format] = { type: "json_object" } if json

      response = post_json("#{endpoint}/chat/completions", body, read_timeout: read_timeout)
      content = response.dig("choices", 0, "message", "content")
      raise Error, "empty completion" if content.blank?
      json ? parse_json(content) : content
    end

    # One tool-use turn. `tools` is the OpenAI function-tools array
    # ({ type: "function", function: { name, description, parameters } }).
    # Returns the raw assistant message Hash, which may carry "tool_calls".
    # The caller appends it verbatim, executes any tool_calls, appends the
    # role:"tool" results, and calls again — the loop lives in the agent
    # runner, not here.
    def chat_with_tools(messages, tools:, temperature: 0.2, max_tokens: 1024, read_timeout: DEFAULT_READ_TIMEOUT)
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        tools: tools,
        tool_choice: "auto"
      }
      response = post_json("#{endpoint}/chat/completions", body, read_timeout: read_timeout)
      message = response.dig("choices", 0, "message")
      raise Error, "empty completion" if message.nil?
      message
    end

    private

    def post_json(url, payload, read_timeout: DEFAULT_READ_TIMEOUT)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = read_timeout

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
