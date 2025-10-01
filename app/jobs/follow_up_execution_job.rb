class FollowUpExecutionJob < ApplicationJob
  queue_as :default

  def perform(scheduled_followup_id)
    scheduled_followup = ScheduledFollowUp.find(scheduled_followup_id)
    
    # Check if the follow-up is still scheduled and not cancelled
    return unless scheduled_followup.scheduled?
    
    # Check if the conversation is still active (open or pending)
    return unless scheduled_followup.conversation.open? || scheduled_followup.conversation.pending?
    
    # Send the follow-up message
    begin
      # Create the message using MessageBuilder
      params = { 
        content: scheduled_followup.message_content, 
        private: false 
      }
      
      mb = Messages::MessageBuilder.new(scheduled_followup.user, scheduled_followup.conversation, params)
      mb.perform
      
      # Mark as sent
      scheduled_followup.mark_as_sent!
      
      Rails.logger.info "Follow-up message sent successfully for conversation #{scheduled_followup.conversation.id}"
      
    rescue StandardError => e
      Rails.logger.error "Failed to send follow-up message: #{e.message}"
      scheduled_followup.mark_as_failed!(e.message)
      raise e
    end
  end
end
