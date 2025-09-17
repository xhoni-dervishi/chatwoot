require 'json'

class Ai::OpenaiService
  DEFAULT_MODEL = 'gpt-5'.freeze
  DEFAULT_ENDPOINT = 'https://api.openai.com/v1'.freeze

  def initialize
    @api_key = get_api_key
    @model = get_model
    @endpoint = get_endpoint
    @client = initialize_client
  end

  def generate_response(conversation_context, custom_prompt)
    messages = build_messages(conversation_context, custom_prompt)
    input_text = convert_messages_to_input(messages)
    
    # Use HTTParty or Net::HTTP for direct API calls
    response = make_responses_api_call(input_text)

    extract_response_text(response)
  rescue StandardError => e
    Rails.logger.error "OpenAI API Error: #{e.message}"
    raise Ai::OpenaiService::ApiError, "Failed to generate AI response: #{e.message}"
  end

  private

  def get_api_key
    GlobalConfigService.load('OPENAI_API_KEY', nil) ||
      raise(ApiError, 'AI OpenAI API key not configured')
  end

  def get_model
    GlobalConfigService.load('OPENAI_MODEL', nil) || DEFAULT_MODEL
  end

  def get_endpoint
    GlobalConfigService.load('OPENAI_ENDPOINT', nil) || DEFAULT_ENDPOINT
  end

  def initialize_client
    OpenAI::Client.new(
      access_token: @api_key,
      uri_base: @endpoint,
      log_errors: Rails.env.development?
    )
  end

  def build_messages(conversation_context, custom_prompt)
    system_message = build_system_message(custom_prompt)
    conversation_messages = build_conversation_messages(conversation_context)
    
    [system_message] + conversation_messages
  end

  def build_system_message(custom_prompt)
    {
      role: 'system',
      content: <<~SYSTEM_PROMPT
        You are a helpful AI assistant for customer support agents. Your role is to generate appropriate responses to customer inquiries based on the conversation context.

        Guidelines:
        - Be helpful, professional, and empathetic
        - Keep responses concise but informative
        - Match the tone and style of the conversation
        - Provide actionable solutions when possible
        - If you need more information, ask clarifying questions
        - Don't make promises about policies or procedures you're unsure about
        - Always be respectful and understanding

        Generate a response that an agent can send directly to the customer.

        Custom prompt: #{custom_prompt}
      SYSTEM_PROMPT
    }
  end

  def build_conversation_messages(conversation_context)
    conversation_context.map do |message|
      {
        role: message[:role],
        content: message[:content]
      }
    end
  end

  def make_responses_api_call(input_text)
    require 'net/http'
    require 'uri'
    
    uri = URI("#{@endpoint}/responses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@api_key}"
    request.body = {
      model: @model,
      input: input_text,
    }.to_json
    
    Rails.logger.info "Request body: #{request.body}"
    
    http.request(request)
  end

  def convert_messages_to_input(messages)
    messages.map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")
  end

  def extract_response_text(response)
    # Log the raw response for debugging
    Rails.logger.info "OpenAI Raw Response Status: #{response.code}"
    Rails.logger.info "OpenAI Raw Response Headers: #{response.to_hash}"
    Rails.logger.info "OpenAI Raw Response Body: #{response.body}"
    
    response_body = JSON.parse(response.body)
    
    # Handle error responses
    if response_body['error']
      error_message = response_body.dig('error', 'message') || 'Unknown OpenAI API error'
      raise ApiError, "OpenAI API error: #{error_message}"
    end
    
    # Handle success responses
    response_body['output'] || response_body['response'] || 
      raise(ApiError, 'Invalid response format from OpenAI API')
  end

  class ApiError < StandardError; end
end
