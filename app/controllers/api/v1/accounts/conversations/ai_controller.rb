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
    service = Ai::ResponseGeneratorService.new(@conversation)
    response = service.generate_response('')
    
    save_draft_messages_to_chat(response)
    
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

  def save_draft_messages_to_chat(ai_response)
    ai_chat_conversation = AiChatConversation.find_or_create_by(
      conversation: @conversation,
      user: current_user
    ) do |chat_conv|
      chat_conv.title = "AI Chat - #{@conversation.contact.name}"
    end

    ai_chat_conversation.add_message(
      role: 'user',
      content: 'Draft a reply'
    )

    ai_chat_conversation.add_message(
      role: 'assistant',
      content: ai_response
    )
  rescue StandardError => e
    Rails.logger.error "Failed to save draft messages to chat: #{e.message}"
  end

  def ensure_ai_enabled
    ai_conversation = @conversation.ai_conversation
    unless ai_conversation&.ai_enabled?
      render json: {
        success: false,
        error: 'AI is not enabled for this conversation'
      }, status: :forbidden
    end
  end
end