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
                 .where('content IS NOT NULL AND content != ? OR id IN (SELECT DISTINCT message_id FROM attachments WHERE message_id = messages.id)', '')
                 .order(created_at: :asc)
                 .limit(max_messages)
  end

  def format_messages_for_ai(messages)
    Rails.logger.info "[AI Context] Processing #{messages.count} messages for AI context"
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
      
      Rails.logger.info "[AI Context] Message #{message.id} has #{message.attachments.count} attachments"
      message.attachments.each do |attachment|
        Rails.logger.info "[AI Context] Attachment: #{attachment.file_type} - #{attachment.file.filename if attachment.file.attached?}"
      end
      
      image_attachments = []
      file_attachments = []
      
      message.attachments.each do |attachment|
        if attachment.file.attached?
          filename = attachment.file.filename.to_s.downcase
          content_type = attachment.file.content_type
          
          # Check if it's an image by both content type and file extension
          is_image = is_image_file?(content_type, filename)
          
          # Check if it's a PDF file
          is_pdf = is_pdf_file?(content_type, filename)
          
          if is_image
            image_attachments << attachment
            Rails.logger.info "[AI Context] Classified as image: #{filename} (#{content_type})"
          elsif is_pdf
            file_attachments << attachment
            Rails.logger.info "[AI Context] Classified as PDF file: #{filename} (#{content_type})"
          else
            Rails.logger.info "[AI Context] Skipping unsupported file type: #{filename} (#{content_type})"
          end
        end
      end
      
      if image_attachments.any?
        Rails.logger.info "[AI Context] Found #{image_attachments.count} image attachments in message #{message.id}"
        message_data[:images] = image_attachments.map do |attachment|
          {
            url: attachment.download_url,
            filename: attachment.file.filename.to_s,
            content_type: attachment.file.content_type
          }
        end
      end
      
      if file_attachments.any?
        Rails.logger.info "[AI Context] Found #{file_attachments.count} file attachments in message #{message.id}"
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
      'user'
    when 'outgoing'
      'assistant'
    else
      'user'
    end
  end

  def format_message_content(message)
    content = message.content.to_s.strip
    
    if content.empty? && message.attachments.any?
      content = "[Image/File attached]"
    end
    
    if message.message_type == 'incoming'
      "#{message.sender.name}: #{content}"
    else
      content
    end
  end

  def add_importance_marker(content, importance_level)
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
    GlobalConfigService.load('AI_MAX_CONTEXT_MESSAGES', DEFAULT_MAX_MESSAGES).to_i
  end

  def is_image_file?(content_type, filename)
    image_content_types = [
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp'
    ]
    
    image_extensions = ['.png', '.jpeg', '.jpg', '.webp', '.gif', '.bmp']
    
    content_type_match = image_content_types.include?(content_type&.downcase)
    extension_match = image_extensions.any? { |ext| filename.end_with?(ext) }
    
    content_type_match && extension_match
  end

  def is_pdf_file?(content_type, filename)
    pdf_content_types = ['application/pdf']
    
    pdf_extensions = ['.pdf']
    
    content_type_match = pdf_content_types.include?(content_type&.downcase)
    extension_match = pdf_extensions.any? { |ext| filename.end_with?(ext) }
    
    content_type_match && extension_match
  end
end
