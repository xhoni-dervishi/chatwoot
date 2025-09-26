class Ai::ConversationContextService
  DEFAULT_MAX_MESSAGES = 25
  RECENT_MESSAGES_WEIGHT = 5

  def initialize(conversation)
    @conversation = conversation
  end

  def build_context
    messages = fetch_recent_messages
    Rails.logger.info "[AI Context] Building context with #{messages.length} messages for conversation #{@conversation.id}"
    
    formatted_messages = format_messages_for_ai(messages)
    
    recent_messages = formatted_messages.last(3)
    Rails.logger.debug "[AI Context] Most recent messages for conversation #{@conversation.id}:"
    recent_messages.each_with_index do |msg, idx|
      Rails.logger.debug "[AI Context] #{idx + 1}. #{msg[:role]}: #{msg[:content][0..100]}..."
    end
    
    formatted_messages
  end

  private

  def fetch_recent_messages
    max_messages = get_max_messages
    
    @conversation.messages
                 .includes(:sender, attachments: :file_attachment)
                 .where(message_type: ['incoming', 'outgoing'])
                 .where.not(content: [nil, ''])
                 .order(created_at: :asc)
                 .limit(max_messages)
  end

  def format_messages_for_ai(messages)
    messages.map.with_index do |message, index|
      content = format_message_content(message)
      
      if index >= messages.length - RECENT_MESSAGES_WEIGHT
        importance_level = messages.length - index
        content = add_importance_marker(content, importance_level)
      end
      
      message_data = {
        role: determine_role(message),
        content: content,
        sender: message.sender.name,
        timestamp: message.created_at.iso8601
      }
      
      image_attachments = message.attachments.select(&:image?)
      if image_attachments.any?
        message_data[:images] = image_attachments.map do |attachment|
          {
            url: attachment.download_url,
            filename: attachment.file.filename.to_s,
            content_type: attachment.file.content_type
          }
        end
      end
      
      file_attachments = message.attachments.select(&:file?)
      if file_attachments.any?
        message_data[:files] = file_attachments.map do |attachment|
          {
            url: attachment.download_url,
            filename: attachment.file.filename.to_s,
            content_type: attachment.file.content_type
          }
        end
      end
      
      message_data
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
