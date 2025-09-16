class Ai::ConversationManagerService
  def initialize(conversation)
    @conversation = conversation
  end

  def enable_ai!
    ai_conversation = @conversation.ai_conversation || @conversation.build_ai_conversation
    ai_conversation.enable_ai!
    ai_conversation
  end

  def disable_ai!
    return unless @conversation.ai_conversation
    @conversation.ai_conversation.disable_ai!
  end

  def ai_enabled?
    @conversation.ai_conversation&.ai_enabled? || false
  end

  def self.enable_ai_for_conversation!(conversation)
    new(conversation).enable_ai!
  end
end
