class Ai::ConversationContextService
  MAX_MESSAGES = 15

  def initialize(conversation)
    @conversation = conversation
  end

  def build_context
    messages = fetch_recent_messages
    format_messages_for_ai(messages)
  end

  private

  def fetch_recent_messages
    @conversation.messages
                 .includes(:sender)
                 .where(message_type: ['incoming', 'outgoing'])
                 .where.not(content: [nil, ''])
                 .order(created_at: :desc)
                 .limit(MAX_MESSAGES)
                 .reverse
  end

  def format_messages_for_ai(messages)
    messages.map do |message|
      {
        role: determine_role(message),
        content: format_message_content(message),
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
end
