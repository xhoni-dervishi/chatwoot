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
          user_message: result[:user_message],
          ai_message: result[:ai_message]
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
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.error "AI Chat Timeout Error: #{e.message}"
    render json: {
      success: false,
      error: 'The AI request timed out. Please try again with a shorter message.'
    }, status: :request_timeout
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

  def get_user_timezone
    # Try to get timezone from request parameters first
    if params[:timezone].present?
      Rails.logger.info "Using timezone from params: #{params[:timezone]}"
      params[:timezone]
    # Try to get timezone offset from request parameters
    elsif params[:timezone_offset].present?
      offset = params[:timezone_offset].to_i
      Rails.logger.info "Using timezone offset from params: #{offset}"
      # Convert offset to timezone name
      case offset
      when -12..-11
        'Pacific/Midway'
      when -10..-9
        'Pacific/Honolulu'
      when -8..-7
        'America/Los_Angeles'
      when -6..-5
        'America/Chicago'
      when -5..-4
        'America/New_York'
      when -3..-2
        'America/Argentina/Buenos_Aires'
      when 0..1
        'Europe/London'
      when 1..2
        'Europe/Paris'
      when 2..3
        'Europe/Berlin'
      when 3..4
        'Europe/Moscow'
      when 5..6
        'Asia/Kolkata'
      when 8..9
        'Asia/Shanghai'
      when 9..10
        'Asia/Tokyo'
      else
        'UTC'
      end
    # Try to get from request headers (browser timezone)
    elsif request.headers['HTTP_X_TIMEZONE'].present?
      Rails.logger.info "Using timezone from headers: #{request.headers['HTTP_X_TIMEZONE']}"
      request.headers['HTTP_X_TIMEZONE']
    # Try to get from Accept-Language header (browser locale) - REMOVED FALLBACK
    # elsif request.headers['HTTP_ACCEPT_LANGUAGE'].present?
    #   locale = request.headers['HTTP_ACCEPT_LANGUAGE'].split(',').first
    #   Rails.logger.info "Using timezone from Accept-Language: #{locale}"
    #   # Map common locales to timezones as fallback
    #   case locale.downcase
    #   when /en-us/, /en-ca/
    #     'America/New_York'
    #   when /en-gb/, /en-au/
    #     'Europe/London'
    #   when /de/, /de-de/
    #     'Europe/Berlin'
    #   when /fr/, /fr-fr/
    #     'Europe/Paris'
    #   else
    #     'UTC'
    #   end
    # Try to get from user model as fallback
    elsif @user.respond_to?(:time_zone) && @user.time_zone.present?
      Rails.logger.info "Using timezone from user model: #{@user.time_zone}"
      @user.time_zone
    else
      Rails.logger.info "Using default timezone: UTC"
      Rails.logger.info "Available headers: #{request.headers.keys.select { |k| k.include?('TIME') || k.include?('ZONE') || k.include?('LOCALE') }}"
      'UTC'
    end
  end

  def get_user_timezone_offset
    # First try to get offset from request parameters (most reliable)
    if params[:timezone_offset].present?
      offset = params[:timezone_offset].to_i
      Rails.logger.info "Using timezone offset from params: #{offset} hours"
      return offset
    end
    
    timezone = get_user_timezone
    
    # Try to parse the timezone and get offset
    begin
      tz = ActiveSupport::TimeZone[timezone]
      if tz
        offset_hours = tz.utc_offset / 3600
        Rails.logger.info "Timezone #{timezone} calculated offset: #{offset_hours} hours"
        offset_hours
      else
        # If timezone string is not recognized, try to parse as offset
        if timezone.match?(/^[+-]\d{1,2}$/)
          offset = timezone.to_i
          Rails.logger.info "Timezone #{timezone} parsed as offset: #{offset} hours"
          offset
        else
          Rails.logger.info "Timezone #{timezone} not recognized, defaulting to 0 hours"
          0 # Default to UTC if parsing fails
        end
      end
    rescue => e
      Rails.logger.error "Error calculating timezone offset for #{timezone}: #{e.message}"
      0 # Default to UTC if parsing fails
    end
  end

  def extractDraftResponse(response)
    return '' if response.blank?
    
    # Check for [DRAFT REPLY] flag (case insensitive) in the first section until end of string or ###
    draft_reply_match = response.match(/\[DRAFT REPLY\]\s*([\s\S]*?)(?=\n###|$)/i)
    if draft_reply_match && draft_reply_match[1]
      return draft_reply_match[1]&.strip || ''
    end
    
    # Check for [Draft Reply] flag (case insensitive) in the first section until end of string or ###
    draft_reply_match_alt = response.match(/\[Draft Reply\]\s*([\s\S]*?)(?=\n###|$)/i)
    if draft_reply_match_alt && draft_reply_match_alt[1]
      return draft_reply_match_alt[1]&.strip || ''
    end
    
    # Check from ### until other ### or end of string
    draft_response_match = response.match(/###\s*([\s\S]*?)(?=\n###|$)/i)
    
    if draft_response_match && draft_response_match[1]
      return draft_response_match[1]&.strip || ''
    end
    
    response
  end

  def handle_follow_up_message(message)
    # Get the conversation context for the AI
    conversation_context = @conversation.messages.where.not(message_type: :activity).order(:created_at).last(5)
    context_text = conversation_context.map { |msg| 
      sender = msg.sender_type == 'Contact' ? msg.sender.name : 'Agent'
      "[#{msg.created_at.strftime('%Y-%m-%d %H:%M')}] #{sender}: #{msg.content}"
    }.join("\n")
    
    # Create a smart prompt that determines the user's intent
    prompt = <<~PROMPT
      You are helping an agent with follow-up message instructions for a customer conversation. 
      
      Conversation context:
      #{context_text}
      
      Current system time (UTC): #{Time.current.utc.iso8601}
      Current system timezone: #{Time.zone.name} (#{Time.zone.utc_offset / 3600} hours from UTC)
      User timezone: #{get_user_timezone} (#{get_user_timezone_offset} hours from UTC)
      
      The agent has given this instruction: "#{message}"
      
      Analyze the instruction and determine if it's:
      1. TIME-RELATED: Changing when to send the follow-up (e.g., "5 Oct, 2025, 04:29:00 PM", "tomorrow", "1 hour later")
      2. MESSAGE-RELATED: Changing the content of the follow-up (e.g., "make it shorter", "more polite", "add urgency")
      3. GENERAL: Creating a new follow-up message
      
      CRITICAL RULES:
      - For TIME-RELATED instructions: Keep the existing message EXACTLY as is, only change the time
      - For MESSAGE-RELATED instructions: Update the message content, keep or suggest new time
      - For GENERAL instructions: Create new message and suggest time
      - When user specifies time without timezone (e.g., "5 Oct, 2025, 05:09:00 PM"), assume it's in the USER'S timezone (#{get_user_timezone})
      - Convert all times to UTC ISO format (e.g., "2025-10-05T15:09:00Z")
      - IMPORTANT: Account for timezone differences when converting to UTC
      CRITICAL TIMEZONE CONVERSION STEPS:
      1. User timezone: #{get_user_timezone} (#{get_user_timezone_offset} hours from UTC)
      2. User input: "5 Oct, 2025, 05:10:00 PM" (this is in their LOCAL timezone)
      3. Convert to UTC: #{get_user_timezone_offset > 0 ? "05:10 PM - #{get_user_timezone_offset} hours = #{(17 - get_user_timezone_offset).to_s.rjust(2, '0')}:10 PM UTC" : "05:10 PM UTC"}
      4. Return UTC time in ISO format: "2025-10-05T#{get_user_timezone_offset > 0 ? (17 - get_user_timezone_offset).to_s.rjust(2, '0') : '17'}:10:00Z"
      5. IMPORTANT: The user will see their LOCAL time in the UI, so return the UTC time correctly
      
      Respond with a JSON object based on the instruction type:
      
      For TIME-RELATED instructions:
      {
        "type": "time_update",
        "message": "Put the actual existing follow-up message content here (the exact message text that was previously suggested)",
        "time": "ISO 8601 timestamp for when to send the follow-up",
        "reasoning": "Brief explanation of the time change"
      }
      
      For MESSAGE-RELATED instructions:
      {
        "type": "message_update", 
        "message": "The updated follow-up message text",
        "time": "ISO 8601 timestamp for when to send the follow-up (default 24 hours from now)",
        "reasoning": "Brief explanation of the message change"
      }
      
      For GENERAL instructions:
      {
        "type": "new_followup",
        "message": "The follow-up message text",
        "time": "ISO 8601 timestamp for when to send the follow-up (default 24 hours from now)",
        "reasoning": "Brief explanation of why this follow-up is needed"
      }
      
      Rules:
      - The message should be customer-facing and professional
      - The time should be in ISO 8601 format and MUST be in the FUTURE
      - For time-only changes, keep the existing message content
      - For message changes, provide a new professional message
      - Current time is: #{Time.current.utc.iso8601}
      - IMPORTANT: Return ONLY valid JSON with proper syntax (no extra quotes, no trailing commas)
      - When parsing dates like "5 Oct, 2025, 04:19:00 PM", convert to UTC ISO format
      - DO NOT wrap the JSON in quotes or markdown code blocks
      - Return the raw JSON object directly
      - CRITICAL: Your response must start with { and end with }
      - DO NOT include any text before or after the JSON
      - DO NOT wrap the JSON in quotes like "{"type": "time_update", ...}"
      
      Example valid JSON for time update:
      {
        "type": "time_update",
        "message": "Hi John, just checking in to see if you still need assistance.",
        "time": "2025-10-05T#{get_user_timezone_offset > 0 ? (17 - get_user_timezone_offset).to_s.rjust(2, '0') : '17'}:10:00Z",
        "reasoning": "Updated timing to specified date and time, converted from user timezone (#{get_user_timezone}) to UTC"
      }
      
      TIMEZONE CONVERSION EXAMPLE:
      - User input: "5 Oct, 2025, 05:10:00 PM" (no timezone specified)
      - User timezone: #{get_user_timezone} (#{get_user_timezone_offset} hours from UTC)
      - Convert to UTC: If user is in UTC+#{get_user_timezone_offset} (+#{get_user_timezone_offset} hours), then 05:10 PM local = #{get_user_timezone_offset > 0 ? "#{(17 - get_user_timezone_offset).to_s.rjust(2, '0')}:10 PM UTC" : "05:10 PM UTC"} = "2025-10-05T#{get_user_timezone_offset > 0 ? (17 - get_user_timezone_offset).to_s.rjust(2, '0') : '17'}:10:00Z"
      - IMPORTANT: When user doesn't specify timezone, ALWAYS assume it's in their local timezone, NOT UTC
      - FINAL STEP: The time you return should be the UTC time, but when displaying to user, show their local time
      
      Return ONLY the JSON object, no other text, no quotes, no markdown.
    PROMPT
    
    # Use OpenAI service directly
    ai_service = Ai::OpenaiService.new
    
    # Create properly formatted messages for the AI
    messages = [
      {
        role: 'system',
        content: prompt
      },
      {
        role: 'user',
        content: message
      }
    ]
    
    ai_response = ai_service.generate_chat_response(messages)
    
    # Parse the JSON response from AI
    begin
      # Clean up the AI response to handle common JSON formatting issues
      cleaned_response = ai_response.strip
      
      # Remove any extra quotes around the entire response
      cleaned_response = cleaned_response.gsub(/^["']|["']$/, '')
      
      # Handle case where AI returns JSON as a string (wrapped in quotes)
      if cleaned_response.start_with?('"') && cleaned_response.end_with?('"')
        cleaned_response = cleaned_response[1..-2] # Remove outer quotes
      end
      
      # Fix common JSON issues
      cleaned_response = cleaned_response.gsub(/""([^"]+)":/, '"\1":') # Fix double quotes around keys
      cleaned_response = cleaned_response.gsub(/,(\s*[}\]])/, '\1') # Remove trailing commas
      
      # Try to extract JSON from markdown code blocks if present
      if cleaned_response.include?('```')
        json_match = cleaned_response.match(/```(?:json)?\s*(\{.*?\})\s*```/m)
        cleaned_response = json_match[1] if json_match
      end
      
      # Try to find JSON object in the response if it's not the entire response
      if !cleaned_response.strip.start_with?('{')
        json_match = cleaned_response.match(/\{.*\}/m)
        cleaned_response = json_match[0] if json_match
      end
      
      # Additional cleanup for the specific case we're seeing
      # Remove any leading/trailing quotes that might still be there
      cleaned_response = cleaned_response.strip
      if cleaned_response.start_with?('"') && cleaned_response.end_with?('"')
        cleaned_response = cleaned_response[1..-2]
      end
      
      # Remove control characters that might cause JSON parsing issues
      cleaned_response = cleaned_response.gsub(/[\x00-\x1F\x7F]/, '')
      
      # If we still have quotes around the JSON, try to extract it
      if cleaned_response.include?('"type":')
        json_start = cleaned_response.index('{')
        json_end = cleaned_response.rindex('}') + 1
        if json_start && json_end
          cleaned_response = cleaned_response[json_start...json_end]
        end
      end
      
      Rails.logger.info "Final cleaned response: #{cleaned_response}"
      
      # Try to parse the JSON
      begin
        followup_data = JSON.parse(cleaned_response)
      rescue JSON::ParserError => e
        Rails.logger.error "JSON parsing failed, trying alternative extraction: #{e.message}"
        
        # Last resort: try to extract JSON from the original response using regex
        json_pattern = /\{\s*"type"\s*:\s*"([^"]+)"\s*,\s*"message"\s*:\s*"([^"]+)"\s*,\s*"time"\s*:\s*"([^"]+)"\s*,\s*"reasoning"\s*:\s*"([^"]+)"\s*\}/
        match = ai_response.match(json_pattern)
        
        if match
          followup_data = {
            'type' => match[1],
            'message' => match[2],
            'time' => match[3],
            'reasoning' => match[4]
          }
          Rails.logger.info "Successfully extracted JSON using regex fallback"
        else
          raise e # Re-raise the original error
        end
      end
      instruction_type = followup_data['type']
      followup_message = followup_data['message']
      
      # Debug logging
      Rails.logger.info "AI Response Parsed Successfully:"
      Rails.logger.info "Instruction Type: #{instruction_type}"
      Rails.logger.info "Message: #{followup_message}"
      Rails.logger.info "Time: #{followup_data['time']}"
      Rails.logger.info "Detected User Timezone: #{get_user_timezone} (#{get_user_timezone_offset} hours from UTC)"
      Rails.logger.info "User Input: #{message}"
      Rails.logger.info "Expected UTC Time Calculation: User entered time - #{get_user_timezone_offset} hours = UTC time"
      
      # Parse and validate the suggested time
      if followup_data['time']
        parsed_time = Time.parse(followup_data['time'])
        # Ensure we're working in UTC to avoid timezone issues
        parsed_time = parsed_time.utc
        # If the suggested time is in the past, use 24 hours from now instead
        suggested_time = parsed_time > Time.current.utc ? parsed_time.iso8601 : 24.hours.from_now.utc.iso8601
      else
        suggested_time = 24.hours.from_now.utc.iso8601
      end
      
      # Create user message (not saved to DB)
      user_message = {
        id: "followup-user-#{Time.current.to_i}",
        role: 'user',
        content: message,
        created_at: Time.current.iso8601
      }
      
      # Create AI response based on instruction type
      case instruction_type
      when 'time_update'
        # For time updates, the AI should return the actual existing message content
        # Convert UTC time back to user's local time for display
        utc_time = Time.parse(suggested_time)
        user_local_time = utc_time.in_time_zone(get_user_timezone)
        
        ai_message = {
          id: "followup-ai-#{Time.current.to_i}",
          role: 'assistant',
          content: "Perfect! I've updated the timing to #{user_local_time.strftime('%B %d, %Y at %I:%M %p')}. Would you like to confirm this schedule?",
          created_at: Time.current.iso8601,
          followUpData: {
            type: 'time_confirmation',
            currentMessage: followup_message, # Use the actual message content from AI
            currentTime: suggested_time,
            scheduledTime: suggested_time,
            reasoning: followup_data['reasoning']
          }
        }
        
        Rails.logger.info "AI Message Response:"
        Rails.logger.info "Content: #{ai_message[:content]}"
        Rails.logger.info "Scheduled Time (UTC): #{suggested_time}"
        Rails.logger.info "User Local Time: #{user_local_time.strftime('%B %d, %Y at %I:%M %p')}"
      when 'message_update'
        # Convert UTC time back to user's local time for display
        utc_time = Time.parse(suggested_time)
        user_local_time = utc_time.in_time_zone(get_user_timezone)
        
        ai_message = {
          id: "followup-ai-#{Time.current.to_i}",
          role: 'assistant',
          content: "I've updated the follow-up message:\n\n\"#{followup_message}\"\n\nSuggested time: #{user_local_time.strftime('%B %d, %Y at %I:%M %p')}\n\nWould you like to proceed with this message?",
          created_at: Time.current.iso8601,
          followUpData: {
            type: 'draft_confirmation',
            draftMessage: followup_message,
            suggestedTime: suggested_time,
            reasoning: followup_data['reasoning']
          }
        }
      else # 'new_followup'
        # Convert UTC time back to user's local time for display
        utc_time = Time.parse(suggested_time)
        user_local_time = utc_time.in_time_zone(get_user_timezone)
        
        ai_message = {
          id: "followup-ai-#{Time.current.to_i}",
          role: 'assistant',
          content: "Here's a follow-up message:\n\n\"#{followup_message}\"\n\nSuggested time: #{user_local_time.strftime('%B %d, %Y at %I:%M %p')}\n\nWould you like to proceed with this message?",
          created_at: Time.current.iso8601,
          followUpData: {
            type: 'draft_confirmation',
            draftMessage: followup_message,
            suggestedTime: suggested_time,
            reasoning: followup_data['reasoning']
          }
        }
      end
      
      { success: true, user_message: user_message, ai_message: ai_message }
      
    rescue JSON::ParserError, ArgumentError => e
      Rails.logger.error "Failed to parse AI JSON response: #{e.message}"
      Rails.logger.error "Original AI Response: #{ai_response}"
      Rails.logger.error "Cleaned Response: #{cleaned_response}"
      # Fallback to old format
      updated_message = extractDraftResponse(ai_response)
      suggested_time = 24.hours.from_now.iso8601
      
      user_message = {
        id: "followup-user-#{Time.current.to_i}",
        role: 'user',
        content: message,
        created_at: Time.current.iso8601
      }
      
      ai_message = {
        id: "followup-ai-#{Time.current.to_i}",
        role: 'assistant',
        content: "Here's a follow-up message:\n\n\"#{updated_message}\"\n\nSuggested time: #{Time.parse(suggested_time).strftime('%B %d, %Y at %I:%M %p')}\n\nWould you like to proceed with this message?",
        created_at: Time.current.iso8601,
        followUpData: {
          type: 'draft_confirmation',
          draftMessage: updated_message,
          suggestedTime: suggested_time,
          reasoning: 'AI response parsing failed, using fallback'
        }
      }
      
      { success: true, user_message: user_message, ai_message: ai_message }
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