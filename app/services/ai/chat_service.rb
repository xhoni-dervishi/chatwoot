class Ai::ChatService
  def initialize(conversation, user)
    @conversation = conversation
    @user = user
    @openai_service = Ai::OpenaiService.new
  end

  def find_or_create_chat_conversation
    @ai_chat_conversation ||= AiChatConversation.find_or_create_by(
      conversation: @conversation,
      user: @user
    ) do |chat_conv|
      chat_conv.title = "AI Chat - #{@conversation.contact.name}"
    end
  end

  def send_message(content)
    chat_conversation = find_or_create_chat_conversation
    
    # Add user message
    user_message = chat_conversation.add_message(
      role: 'user',
      content: content
    )

    # Generate AI response
    ai_response = generate_ai_response(chat_conversation)
    
    # Add AI response
    ai_message = chat_conversation.add_message(
      role: 'assistant',
      content: ai_response
    )

    {
      user_message: user_message,
      ai_message: ai_message,
      chat_conversation: chat_conversation
    }
  rescue StandardError => e
    Rails.logger.error "AI Chat Service Error: #{e.message}"
    raise Ai::ChatService::ChatError, e.message
  end

  def get_chat_history
    chat_conversation = find_or_create_chat_conversation
    chat_conversation.ai_chat_messages.order(:created_at)
  end

  def clear_chat_history
    chat_conversation = find_or_create_chat_conversation
    chat_conversation.ai_chat_messages.destroy_all
    chat_conversation
  end

  private

  def generate_ai_response(chat_conversation)
    messages = build_chat_messages(chat_conversation)
    
    response = @openai_service.generate_chat_response(messages)
    
    response
  rescue Ai::OpenaiService::ApiError => e
    Rails.logger.error "AI Chat Generation Failed: #{e.message}"
    raise Ai::ChatService::ChatError, "Failed to generate AI response: #{e.message}"
  end

  def build_chat_messages(chat_conversation)
    system_message = build_chat_system_message
    conversation_context = chat_conversation.conversation_context
    chat_history = chat_conversation.ai_chat_messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content
      }
    end

    [system_message] + conversation_context + chat_history
  end

  def build_chat_system_message
    {
      role: 'system',
      content: <<~SYSTEM_PROMPT
        [Identity]
        You are a helpful and friendly AI assistant for support agents of Cakeberg. You are integrated into an omnichannel CRM system with access to conversation histories. Your primary role is to assist support agents by answering questions, providing insights, and helping with customer support tasks.

        [Context]
        You are chatting with a support agent who is working on a customer conversation. You have access to the full conversation history between the customer and the agent, and you can help the agent understand the situation, suggest responses, or answer questions about the conversation.

        [Response Guidelines]
        - Use natural, polite, and conversational language that is clear and easy to follow.
        - Reply in the language the agent is using.
        - Provide helpful and relevant responses based on the conversation context.
        - You can analyze the conversation history and provide insights.
        - You can suggest responses or help with customer support tasks.
        - If the query is unclear, ask clarifying questions.
        - Be concise but thorough in your responses.
        - Focus on being helpful to the support agent.

        [Business Context]
        Cakeberg is a PVD-registered home bakery specializing in custom cakes, wedding cakes, cookies, macarons, cupcakes, and other specialty treats. The business offers delivery-only service and accepts orders via Facebook and WhatsApp.

        [Instructions]
        - Help the agent understand customer needs and situations
        - Suggest appropriate responses when asked
        - Provide insights about the conversation
        - Answer questions about Cakeberg's services and policies
        - Be a helpful copilot for the support agent
      SYSTEM_PROMPT
    }
  end

  class ChatError < StandardError; end
end
