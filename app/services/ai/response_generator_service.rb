class Ai::ResponseGeneratorService
  def initialize(conversation)
    @conversation = conversation
    @openai_service = Ai::OpenaiService.new
    @context_service = Ai::ConversationContextService.new(conversation)
  end

  def generate_response(custom_prompt)
    validate_conversation
    context = @context_service.build_context
    validate_context(context)
    
    response = @openai_service.generate_response(context, custom_prompt)
    
    response
  rescue Ai::OpenaiService::ApiError => e
    Rails.logger.error "[AI Response] Generation Failed for conversation #{@conversation.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
    raise Ai::ResponseGeneratorService::GenerationError, e.message
  rescue StandardError => e
    Rails.logger.error "[AI Response] Unexpected error for conversation #{@conversation.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
    raise Ai::ResponseGeneratorService::GenerationError, "Failed to generate AI response"
  end

  private

  def validate_conversation
    raise GenerationError, "Conversation not found" if @conversation.blank?
    raise GenerationError, "Conversation has no messages" if @conversation.messages.empty?
  end

  def validate_context(context)
    raise GenerationError, "No conversation context available" if context.blank?
    raise GenerationError, "Insufficient conversation context" if context.length < 1
  end

  class GenerationError < StandardError; end
end
