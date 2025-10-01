class Ai::FollowUpSchedulingService
  def initialize(conversation, user)
    @conversation = conversation
    @user = user
    @openai_service = Ai::OpenaiService.new
  end

  def analyze_conversation_for_followup
    validate_conversation
    
    last_message = @conversation.messages.where.not(message_type: :activity).order(:created_at).last
    return { should_followup: false, reason: "No messages found" } unless last_message
    
    # Check if last message is from customer
    if last_message.sender_type == 'Contact'
      return { 
        should_followup: false, 
        reason: "There's nothing to follow up on right now. The last message is from the customer."
      }
    end
    
    # If last message is from agent, check if enough time has passed
    if last_message.sender_type == 'User'
      return generate_followup_suggestion(last_message)
    end
    
    # Fallback: Check if customer has replied since last agent message
    agent_messages_since_customer = count_agent_messages_since_last_customer_message
    if agent_messages_since_customer == 0
      return { 
        should_followup: false, 
        reason: "There's nothing to follow up on right now. No agent messages since customer's last message."
      }
    end
    
    # Generate follow-up suggestion
    generate_followup_suggestion(last_message)
  end

  def generate_followup_suggestion(last_message)
    context = build_followup_context(last_message)
    prompt = build_followup_prompt(context)
    
    response = @openai_service.generate_response(context, prompt)
    
    # Parse the AI response to extract draft message and suggested time
    parsed_response = parse_followup_response(response)
    
    {
      should_followup: true,
      draft_message: parsed_response[:draft_message],
      suggested_time: parsed_response[:suggested_time],
      reasoning: parsed_response[:reasoning]
    }
  rescue StandardError => e
    Rails.logger.error "Follow-up analysis failed: #{e.message}"
    {
      should_followup: false,
      reason: "Failed to analyze conversation for follow-up: #{e.message}"
    }
  end

  def create_scheduled_followup(message_content, scheduled_at, metadata = {})
    scheduled_followup = ScheduledFollowUp.create!(
      conversation: @conversation,
      user: @user,
      message_content: message_content,
      scheduled_at: scheduled_at,
      metadata: metadata
    )
    
    # Schedule the job
    scheduled_followup.schedule_job!
    
    scheduled_followup
  end

  def update_followup_draft(scheduled_followup_id, new_content, user_request = nil)
    scheduled_followup = ScheduledFollowUp.find(scheduled_followup_id)
    
    # If user provided a request to modify the draft, use AI to update it
    if user_request.present?
      updated_content = generate_updated_draft(scheduled_followup.message_content, user_request)
      scheduled_followup.update!(message_content: updated_content)
    else
      scheduled_followup.update!(message_content: new_content)
    end
    
    scheduled_followup
  end

  def update_followup_time(scheduled_followup_id, new_time)
    scheduled_followup = ScheduledFollowUp.find(scheduled_followup_id)
    
    # Cancel existing job
    scheduled_followup.cancel_job!
    
    # Update time and reschedule
    scheduled_followup.update!(scheduled_at: new_time)
    scheduled_followup.schedule_job!
    
    scheduled_followup
  end

  def cancel_followup(scheduled_followup_id)
    scheduled_followup = ScheduledFollowUp.find(scheduled_followup_id)
    
    # Cancel the job and mark as cancelled
    scheduled_followup.cancel_job!
    
    scheduled_followup
  end

  private

  def validate_conversation
    raise ArgumentError, "Conversation not found" if @conversation.blank?
    raise ArgumentError, "User not found" if @user.blank?
  end

  def count_agent_messages_since_last_customer_message
    messages = @conversation.messages.where.not(message_type: :activity).order(:created_at)
    last_customer_message_index = messages.rindex { |msg| msg.sender_type == 'Contact' }
    
    return 0 unless last_customer_message_index
    
    agent_messages_count = 0
    messages[(last_customer_message_index + 1)..-1].each do |msg|
      agent_messages_count += 1 if msg.sender_type == 'User'
    end
    
    agent_messages_count
  end

  def build_followup_context(last_message)
    # Get recent conversation context
    context_service = Ai::ConversationContextService.new(@conversation)
    context = context_service.build_context
    
    # Add specific follow-up context
    context << {
      role: 'system',
      content: "Last agent message: #{last_message.content} (sent at #{last_message.created_at})"
    }
    
    context
  end

  def build_followup_prompt(context)
    customer_name = @conversation.contact.name
    last_agent_message = @conversation.messages.non_activity_messages.where(sender_type: 'User').last
    
    <<~PROMPT
      Based on this conversation, I need to suggest a follow-up message for the customer "#{customer_name}".
      
      The last agent message was: "#{last_agent_message&.content}"
      
      Please provide a follow-up suggestion in the following JSON format:
      {
        "reasoning": "Brief explanation of why a follow-up is needed",
        "draft_message": "The suggested follow-up message text",
        "suggested_time_hours": 24
      }
      
      Guidelines:
      - The message should be polite and professional
      - Include the customer's name: #{customer_name}
      - Keep it concise but friendly
      - Suggest 24 hours as default unless there's urgency
      - Make it contextually relevant to the conversation
    PROMPT
  end

  def parse_followup_response(response)
    begin
      # Try to parse JSON response
      parsed = JSON.parse(response)
      {
        reasoning: parsed['reasoning'] || 'Follow-up needed based on conversation analysis',
        draft_message: parsed['draft_message'] || 'Hi, just checking in to see if you need any further assistance.',
        suggested_time: (parsed['suggested_time_hours'] || 24).hours.from_now
      }
    rescue JSON::ParserError
      # Fallback if AI doesn't return proper JSON
      {
        reasoning: 'Follow-up needed based on conversation analysis',
        draft_message: extract_draft_from_text(response),
        suggested_time: 24.hours.from_now
      }
    end
  end

  def extract_draft_from_text(text)
    # Simple extraction - look for text that seems like a message
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    
    # Look for lines that start with quotes or seem like messages
    message_line = lines.find { |line| 
      line.match?(/^["']/) || 
      line.match?(/^Hi\s+/i) || 
      line.match?(/^Hello\s+/i) ||
      line.match?(/^Thanks?\s+/i)
    }
    
    message_line || "Hi #{@conversation.contact.name}, just checking in to see if you need any further assistance."
  end

  def generate_updated_draft(current_content, user_request)
    prompt = <<~PROMPT
      The current follow-up message is: "#{current_content}"
      
      The user wants to modify it with this request: "#{user_request}"
      
      Please provide an updated version of the message that incorporates the user's request while maintaining professionalism and the original intent.
      
      Return only the updated message text, nothing else.
    PROMPT
    
    @openai_service.generate_response([], prompt)
  rescue StandardError => e
    Rails.logger.error "Failed to update draft: #{e.message}"
    current_content
  end

  def generate_default_followup_message
    customer_name = @conversation.contact.name
    "Hi #{customer_name}, just checking in to see if you need any further assistance or have any questions about our previous conversation."
  end

end
