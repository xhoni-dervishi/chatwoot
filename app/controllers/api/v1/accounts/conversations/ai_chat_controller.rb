class Api::V1::Accounts::Conversations::AiChatController < Api::V1::Accounts::Conversations::BaseController
  before_action :set_user

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat
  # 
  # Send a message to AI chat and get response
  # 
  # Headers:
  #   Authorization: Bearer <access_token>
  #   Content-Type: application/json
  #
  # Request Body:
  #   {
  #     "message": "What should I say to this customer about their order?"
  #   }
  #
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "user_message": {
  #         "id": 123,
  #         "role": "user",
  #         "content": "What should I say to this customer about their order?",
  #         "created_at": "2024-12-20T12:00:00Z"
  #       },
  #       "ai_message": {
  #         "id": 124,
  #         "role": "assistant", 
  #         "content": "Based on the conversation, I suggest...",
  #         "created_at": "2024-12-20T12:00:01Z"
  #       },
  #       "chat_conversation": {
  #         "id": 45,
  #         "title": "AI Chat - John Doe",
  #         "message_count": 2
  #       }
  #     }
  #
  #   Error (422):
  #     {
  #       "success": false,
  #       "error": "Message content is required"
  #     }
  #
  #   Error (403):
  #     {
  #       "success": false,
  #       "error": "AI is not enabled for this conversation"
  #     }
  def send_message
    message_content = params[:message]&.strip
    
    if message_content.blank?
      render json: {
        success: false,
        error: 'Message content is required'
      }, status: :unprocessable_entity
      return
    end

    service = Ai::ChatService.new(@conversation, @user)
    result = service.send_message(message_content)
    
    render json: {
      success: true,
      user_message: format_message(result[:user_message]),
      ai_message: format_message(result[:ai_message]),
      chat_conversation: format_chat_conversation(result[:chat_conversation])
    }
  rescue Ai::ChatService::ChatError => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "AI Chat Controller Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while processing your message'
    }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat
  # 
  # Get AI chat history for this conversation
  # 
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "messages": [
  #         {
  #           "id": 123,
  #           "role": "user",
  #           "content": "What should I say?",
  #           "created_at": "2024-12-20T12:00:00Z"
  #         },
  #         {
  #           "id": 124,
  #           "role": "assistant",
  #           "content": "I suggest...",
  #           "created_at": "2024-12-20T12:00:01Z"
  #         }
  #       ],
  #       "chat_conversation": {
  #         "id": 45,
  #         "title": "AI Chat - John Doe",
  #         "message_count": 2
  #       }
  #     }
  def get_history
    service = Ai::ChatService.new(@conversation, @user)
    chat_conversation = service.find_or_create_chat_conversation
    messages = service.get_chat_history
    
    render json: {
      success: true,
      messages: messages.map { |msg| format_message(msg) },
      chat_conversation: format_chat_conversation(chat_conversation)
    }
  rescue StandardError => e
    Rails.logger.error "AI Chat History Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while fetching chat history'
    }, status: :internal_server_error
  end

  # DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat
  # 
  # Clear AI chat history for this conversation
  # 
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "message": "Chat history cleared successfully"
  #     }
  def clear_history
    service = Ai::ChatService.new(@conversation, @user)
    service.clear_chat_history
    
    render json: {
      success: true,
      message: 'Chat history cleared successfully'
    }
  rescue StandardError => e
    Rails.logger.error "AI Chat Clear Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while clearing chat history'
    }, status: :internal_server_error
  end

  private

  def set_user
    @user = current_user
  end

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

  def format_message(message)
    {
      id: message.id,
      role: message.role,
      content: message.content,
      created_at: message.created_at.iso8601
    }
  end

  def format_chat_conversation(chat_conversation)
    {
      id: chat_conversation.id,
      title: chat_conversation.title,
      message_count: chat_conversation.message_count,
      created_at: chat_conversation.created_at.iso8601,
      updated_at: chat_conversation.updated_at.iso8601
    }
  end
end
