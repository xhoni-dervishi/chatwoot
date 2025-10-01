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
    follow_up_mode = params[:follow_up_mode] == true || params[:follow_up_mode] == 'true'
    
    if message_content.blank?
      render json: {
        success: false,
        error: 'Message content is required'
      }, status: :unprocessable_entity
      return
    end

    if follow_up_mode
      # Handle follow-up mode message
      result = handle_follow_up_message(message_content)
      
      if result[:success]
        render json: {
          success: true,
          user_message: format_message(result[:user_message]),
          ai_message: format_message(result[:ai_message])
        }
      else
        render json: {
          success: false,
          error: result[:error]
        }, status: :internal_server_error
      end
    else
      # Normal AI chat mode
      service = Ai::ChatService.new(@conversation, @user)
      result = service.send_message(message_content)
      
      render json: {
        success: true,
        user_message: format_message(result[:user_message]),
        ai_message: format_message(result[:ai_message]),
        chat_conversation: format_chat_conversation(result[:chat_conversation])
      }
    end
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

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/schedule_followup
  # 
  # Analyze conversation and suggest a follow-up message
  # 
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "should_followup": true,
  #       "draft_message": "Hi John, just checking in to see if you'd still like to proceed with your order.",
  #       "suggested_time": "2024-12-21T10:00:00Z",
  #       "reasoning": "Customer hasn't replied to agent's last message about order details"
  #     }
  #
  #   Success (200) - No followup needed:
  #     {
  #       "success": true,
  #       "should_followup": false,
  #       "reason": "There's nothing to follow up on right now. The last message is from the customer."
  #     }
  def schedule_followup
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    result = service.analyze_conversation_for_followup
    
    render json: {
      success: true,
      **result
    }
  rescue StandardError => e
    Rails.logger.error "Schedule Follow-up Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while analyzing conversation for follow-up'
    }, status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/create_followup
  # 
  # Create a scheduled follow-up message
  # 
  # Request Body:
  #   {
  #     "message_content": "Hi John, just checking in...",
  #     "scheduled_at": "2024-12-21T10:00:00Z",
  #     "metadata": {}
  #   }
  #
  # Response:
  #   Success (200):
  #     {
  #       "success": true,
  #       "scheduled_followup": {
  #         "id": 123,
  #         "message_content": "Hi John, just checking in...",
  #         "scheduled_at": "2024-12-21T10:00:00Z",
  #         "status": "scheduled"
  #       }
  #     }
  def create_followup
    message_content = params[:message_content]&.strip
    scheduled_at = params[:scheduled_at]
    metadata = params[:metadata] || {}
    
    if message_content.blank?
      render json: {
        success: false,
        error: 'Message content is required'
      }, status: :unprocessable_entity
      return
    end
    
    if scheduled_at.blank?
      render json: {
        success: false,
        error: 'Scheduled time is required'
      }, status: :unprocessable_entity
      return
    end
    
    begin
      scheduled_time = Time.parse(scheduled_at)
    rescue ArgumentError
      render json: {
        success: false,
        error: 'Invalid scheduled time format'
      }, status: :unprocessable_entity
      return
    end
    
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    scheduled_followup = service.create_scheduled_followup(message_content, scheduled_time, metadata)
    
    render json: {
      success: true,
      scheduled_followup: format_scheduled_followup(scheduled_followup)
    }
  rescue StandardError => e
    Rails.logger.error "Create Follow-up Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while creating scheduled follow-up'
    }, status: :internal_server_error
  end

  # PUT /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/update_followup_draft/:id
  # 
  # Update the draft message for a scheduled follow-up
  # 
  # Request Body:
  #   {
  #     "new_content": "Updated message content",
  #     "user_request": "Make it more polite"
  #   }
  def update_followup_draft
    scheduled_followup_id = params[:id]
    new_content = params[:new_content]&.strip
    user_request = params[:user_request]&.strip
    
    if new_content.blank? && user_request.blank?
      render json: {
        success: false,
        error: 'Either new content or user request is required'
      }, status: :unprocessable_entity
      return
    end
    
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    scheduled_followup = service.update_followup_draft(scheduled_followup_id, new_content, user_request)
    
    render json: {
      success: true,
      scheduled_followup: format_scheduled_followup(scheduled_followup)
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Scheduled follow-up not found'
    }, status: :not_found
  rescue StandardError => e
    Rails.logger.error "Update Follow-up Draft Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while updating follow-up draft'
    }, status: :internal_server_error
  end

  # PUT /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/update_followup_time/:id
  # 
  # Update the scheduled time for a follow-up
  # 
  # Request Body:
  #   {
  #     "scheduled_at": "2024-12-21T12:00:00Z"
  #   }
  def update_followup_time
    scheduled_followup_id = params[:id]
    scheduled_at = params[:scheduled_at]
    
    if scheduled_at.blank?
      render json: {
        success: false,
        error: 'Scheduled time is required'
      }, status: :unprocessable_entity
      return
    end
    
    begin
      scheduled_time = Time.parse(scheduled_at)
    rescue ArgumentError
      render json: {
        success: false,
        error: 'Invalid scheduled time format'
      }, status: :unprocessable_entity
      return
    end
    
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    scheduled_followup = service.update_followup_time(scheduled_followup_id, scheduled_time)
    
    render json: {
      success: true,
      scheduled_followup: format_scheduled_followup(scheduled_followup)
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Scheduled follow-up not found'
    }, status: :not_found
  rescue StandardError => e
    Rails.logger.error "Update Follow-up Time Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while updating follow-up time'
    }, status: :internal_server_error
  end

  # GET /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/existing_followups
  def existing_followups
    followups = ScheduledFollowUp.where(conversation: @conversation, user: @user)
                               .where(status: [:pending, :scheduled])
                               .order(:scheduled_at)
    
    render json: {
      success: true,
      followups: followups.map { |followup| format_scheduled_followup(followup) }
    }
  rescue StandardError => e
    Rails.logger.error "Get Existing Follow-ups Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while fetching existing follow-ups'
    }, status: :internal_server_error
  end

  # DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/ai_chat/cancel_followup/:id
  def cancel_followup
    scheduled_followup_id = params[:id]
    
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    scheduled_followup = service.cancel_followup(scheduled_followup_id)
    
    render json: {
      success: true,
      message: 'Follow-up cancelled successfully'
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Scheduled follow-up not found'
    }, status: :not_found
  rescue StandardError => e
    Rails.logger.error "Cancel Follow-up Error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred while cancelling follow-up'
    }, status: :internal_server_error
  end

  private

  def handle_follow_up_message(message)
    # In follow-up mode, we need to determine what the user is trying to do
    # based on the message content and current context
    
    # Check if this is a draft editing instruction
    if message.downcase.include?('shorter') || 
       message.downcase.include?('polite') || 
       message.downcase.include?('longer') ||
       message.downcase.include?('change') ||
       message.downcase.include?('edit') ||
       message.downcase.include?('make it')
      handle_draft_editing_instruction(message)
    # Check if this is a time editing instruction
    elsif message.downcase.include?('minutes') || 
          message.downcase.include?('hours') || 
          message.downcase.include?('tomorrow') ||
          message.downcase.include?('later') ||
          message.downcase.include?('schedule')
      handle_time_editing_instruction(message)
    else
      # Default follow-up instruction processing
      handle_general_follow_up_instruction(message)
    end
  end

  def handle_draft_editing_instruction(message)
    # Use AI to generate an updated follow-up message based on the instruction
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    
    # Get the current conversation context to understand what we're following up on
    last_message = @conversation.messages.where.not(message_type: :activity).order(:created_at).last
    context = "The last message was: \"#{last_message&.content}\""
    
    # Generate a follow-up message based on the user's instruction
    conversation_context = [{
      role: 'system',
      content: "You are a helpful assistant that writes professional follow-up messages for customer service conversations."
    }, {
      role: 'user', 
      content: "Based on this conversation context: #{context}\n\nPlease write a follow-up message that is #{message.downcase}. Make it professional and helpful."
    }]
    
    # Use the AI service to generate the updated message
    ai_service = Ai::OpenaiService.new
    ai_response = ai_service.generate_response(conversation_context, "Write a follow-up message")
    
    # Extract just the draft message from the AI response
    # The AI returns a formatted response, we need to extract the actual draft
    if ai_response.include?('[DRAFT REPLY]')
      updated_message = ai_response.split('[DRAFT REPLY]').last.strip
    else
      # Fallback: use the entire response if no draft marker found
      updated_message = ai_response
    end
    
    # Create user message
    user_message = {
      id: "user-#{Time.current.to_i}",
      role: 'user',
      content: message,
      created_at: Time.current.iso8601
    }
    
    # Create AI response with updated draft
    ai_message = {
      id: "ai-#{Time.current.to_i}",
      role: 'assistant',
      content: "I've updated the follow-up message:\n\n\"#{updated_message}\"\n\nWould you like to proceed with this message?",
      created_at: Time.current.iso8601,
      followUpData: {
        type: 'draft_confirmation',
        draftMessage: updated_message,
        existingFollowupId: nil
      }
    }
    
    { success: true, user_message: user_message, ai_message: ai_message }
  end

  def handle_time_editing_instruction(message)
    # Parse the time instruction and calculate the new time
    new_time = parse_time_instruction(message, Time.current)
    
    # Create user message
    user_message = {
      id: "user-#{Time.current.to_i}",
      role: 'user',
      content: message,
      created_at: Time.current.iso8601
    }
    
    # Create AI response with updated time
    ai_message = {
      id: "ai-#{Time.current.to_i}",
      role: 'assistant',
      content: "Perfect! I've updated the timing to #{new_time.strftime('%B %d, %Y at %I:%M %p')}. Would you like to confirm this schedule?",
      created_at: Time.current.iso8601,
      followUpData: {
        type: 'time_confirmation',
        draftMessage: nil, # This will be set by the frontend
        scheduledTime: new_time.iso8601
      }
    }
    
    { success: true, user_message: user_message, ai_message: ai_message }
  end

  def handle_draft_editing(message, follow_up_data)
    current_message = follow_up_data['current_message']
    existing_followup_id = follow_up_data['existingFollowupId']
    
    # Use AI to update the draft based on user instruction
    service = Ai::FollowUpSchedulingService.new(@conversation, @user)
    updated_message = service.generate_updated_draft(current_message, message)
    
    # Create user message
    user_message = {
      id: "user-#{Time.current.to_i}",
      role: 'user',
      content: message,
      created_at: Time.current.iso8601
    }
    
    # Create AI response with updated draft
    ai_message = {
      id: "ai-#{Time.current.to_i}",
      role: 'assistant',
      content: "I've updated the follow-up message:\n\n\"#{updated_message}\"\n\nWould you like to proceed with this message?",
      created_at: Time.current.iso8601,
      followUpData: {
        type: 'draft_confirmation',
        draftMessage: updated_message,
        existingFollowupId: existing_followup_id
      }
    }
    
    { success: true, user_message: user_message, ai_message: ai_message }
  end

  def handle_time_editing(message, follow_up_data)
    current_time = follow_up_data['current_time']
    current_message = follow_up_data['current_message']
    
    # Parse time instruction and calculate new time
    new_time = parse_time_instruction(message, current_time)
    
    # Create user message
    user_message = {
      id: "user-#{Time.current.to_i}",
      role: 'user',
      content: message,
      created_at: Time.current.iso8601
    }
    
    # Create AI response with updated time
    ai_message = {
      id: "ai-#{Time.current.to_i}",
      role: 'assistant',
      content: "Perfect! I've updated the timing to #{new_time.strftime('%B %d, %Y at %I:%M %p')}. Would you like to confirm this schedule?",
      created_at: Time.current.iso8601,
      followUpData: {
        type: 'time_confirmation',
        draftMessage: current_message,
        scheduledTime: new_time.iso8601
      }
    }
    
    { success: true, user_message: user_message, ai_message: ai_message }
  end

  def handle_general_follow_up_instruction(message)
    # Use AI to process general follow-up instructions
    service = Ai::ChatService.new(@conversation, @user)
    result = service.send_message(message)
    
    # Format the messages for the frontend
    user_message = {
      id: result[:user_message].id,
      role: result[:user_message].role,
      content: result[:user_message].content,
      created_at: result[:user_message].created_at.iso8601
    }
    
    ai_message = {
      id: result[:ai_message].id,
      role: result[:ai_message].role,
      content: result[:ai_message].content,
      created_at: result[:ai_message].created_at.iso8601
    }
    
    { success: true, user_message: user_message, ai_message: ai_message }
  end

  def parse_time_instruction(instruction, current_time)
    instruction = instruction.downcase.strip
    
    case instruction
    when /(\d+)\s*minutes?\s*(?:from\s*now|later)/
      minutes = $1.to_i
      Time.current + minutes.minutes
    when /(\d+)\s*hours?\s*(?:from\s*now|later)/
      hours = $1.to_i
      Time.current + hours.hours
    when /(\d+)\s*days?\s*(?:from\s*now|later)/
      days = $1.to_i
      Time.current + days.days
    when /tomorrow/
      Time.current + 1.day
    when /next\s*week/
      Time.current + 1.week
    else
      # Default to 24 hours from now if we can't parse
      Time.current + 24.hours
    end
  end

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

          def format_scheduled_followup(scheduled_followup)
            {
              id: scheduled_followup.id,
              message_content: scheduled_followup.message_content,
              scheduled_at: scheduled_followup.scheduled_at.iso8601,
              status: scheduled_followup.status,
              metadata: scheduled_followup.metadata,
              created_at: scheduled_followup.created_at.iso8601,
              updated_at: scheduled_followup.updated_at.iso8601
            }
          end

end
