class Ai::ConversationContextService
  DEFAULT_MAX_MESSAGES = 25  # Increased from 15 to provide better context
  RECENT_MESSAGES_WEIGHT = 3  # Number of recent messages to emphasize

  def initialize(conversation)
    @conversation = conversation
  end

  def build_context
    messages = fetch_recent_messages
    format_messages_for_ai(messages)
  end

  private

  def fetch_recent_messages
    max_messages = get_max_messages
    
    @conversation.messages
                 .includes(:sender)
                 .where(message_type: ['incoming', 'outgoing'])
                 .where.not(content: [nil, ''])
                 .order(created_at: :desc)
                 .limit(max_messages)
                 .reverse
  end

  def format_messages_for_ai(messages)
    messages.map.with_index do |message, index|
      content = format_message_content(message)
      
      # Add importance weighting for recent messages
      if index >= messages.length - RECENT_MESSAGES_WEIGHT
        content = add_importance_marker(content, messages.length - index)
      end
      
      {
        role: determine_role(message),
        content: content,
        sender: message.sender.name,
        timestamp: message.created_at.iso8601
      }
    end
  end

  def determine_role(message)
    case message.message_type
    when 'incoming'
      'user'  # Customer message
    when 'outgoing'
      'assistant'  # Agent response
    else
      'user'
    end
  end

  def format_message_content(message)
    content = message.content.to_s.strip
    
    # Add sender context for better AI understanding
    if message.message_type == 'incoming'
      "#{message.sender.name}: #{content}"
    else
      content
    end
  end

  def add_importance_marker(content, importance_level)
    # Add markers to indicate message importance to AI
    case importance_level
    when 1
      "[MOST RECENT] #{content}"
    when 2
      "[VERY RECENT] #{content}"
    when 3
      "[RECENT] #{content}"
    when 4
      "[RECENT] #{content}"
    when 5
      "[RECENT] #{content}"
    else
      content
    end
  end

  def get_max_messages
    # Allow configuration via GlobalConfigService
    GlobalConfigService.load('AI_MAX_CONTEXT_MESSAGES', DEFAULT_MAX_MESSAGES).to_i
  end
end
