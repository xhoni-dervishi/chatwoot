class Api::V1::Accounts::Conversations::AiController < Api::V1::Accounts::Conversations::BaseController
  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/ai
  # 
  # Generates an AI response based on the conversation context
  # 
  # Headers:
  #   Authorization: Bearer <access_token>
  #   Content-Type: application/json
  #
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "response": "Thank you for contacting us. I understand you're having issues with...",
  #       "conversation_id": 123
  #     }
  #
  #   Error (422):
  #     {
  #       "success": false,
  #       "error": "No conversation context available"
  #     }
  #
  #   Error (403):
  #     {
  #       "success": false,
  #       "error": "AI is not enabled for this conversation"
  #     }
  #
  #   Error (500):
  #     {
  #       "success": false,
  #       "error": "An unexpected error occurred while generating AI response"
  #     }
  def generate_response
    custom_prompt = params[:customPrompt] || ''
    service = Ai::ResponseGeneratorService.new(@conversation)
    response = service.generate_response(custom_prompt)
    
    render json: {
      success: true,
      response: response,
      conversation_id: @conversation.id
    }
  rescue Ai::ResponseGeneratorService::GenerationError => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "AI Controller Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while generating AI response'
    }, status: :internal_server_error
  end

  private

  def ensure_ai_enabled
    # Check if AI is enabled for this conversation
    ai_conversation = @conversation.ai_conversation
    unless ai_conversation&.ai_enabled?
      render json: {
        success: false,
        error: 'AI is not enabled for this conversation'
      }, status: :forbidden
    end
  end
end