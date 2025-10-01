# == Schema Information
#
# Table name: scheduled_follow_ups
#
#  id              :bigint           not null, primary key
#  message_content :text             not null
#  metadata        :jsonb
#  scheduled_at    :datetime         not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_scheduled_follow_ups_on_conversation_id                   (conversation_id)
#  index_scheduled_follow_ups_on_conversation_id_and_scheduled_at  (conversation_id,scheduled_at)
#  index_scheduled_follow_ups_on_metadata                          (metadata) USING gin
#  index_scheduled_follow_ups_on_status_and_scheduled_at           (status,scheduled_at)
#  index_scheduled_follow_ups_on_user_id                           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (user_id => users.id)
#
class ScheduledFollowUp < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :message_content, presence: true
  validates :scheduled_at, presence: true
  validates :status, presence: true

  enum status: {
    pending: 0,
    scheduled: 1,
    sent: 2,
    cancelled: 3,
    failed: 4
  }

  scope :pending, -> { where(status: :pending) }
  scope :scheduled, -> { where(status: :scheduled) }
  scope :due_for_sending, -> { where('scheduled_at <= ?', Time.current) }
  scope :for_conversation, ->(conversation) { where(conversation: conversation) }
  scope :for_user, ->(user) { where(user: user) }

  def schedule_job!
    return false if scheduled?
    
    # Schedule the job using ActiveJob
    job = FollowUpExecutionJob.set(wait_until: scheduled_at).perform_later(id)
    
    # Update metadata with job ID and set status to scheduled
    update!(
      status: :scheduled,
      metadata: metadata.merge(job_id: job.job_id)
    )
    
    true
  end

  def cancel_job!
    return false unless scheduled?
    
    # Cancel the ActiveJob if it exists
    if metadata['job_id'].present?
      begin
        # For ActiveJob, we need to search through the scheduled set differently
        scheduled_set = Sidekiq::ScheduledSet.new
        job_to_delete = scheduled_set.find { |job| 
          job.args.first['job_id'] == metadata['job_id'] && 
          job.args.first['job_class'] == 'FollowUpExecutionJob'
        }
        
        if job_to_delete
          job_to_delete.delete
          Rails.logger.info "Successfully cancelled Sidekiq job #{metadata['job_id']}"
        else
          Rails.logger.warn "Could not find Sidekiq job #{metadata['job_id']} to cancel"
        end
      rescue => e
        Rails.logger.warn "Could not cancel job #{metadata['job_id']}: #{e.message}"
      end
    end
    
    update!(status: :cancelled)
    true
  end

  def mark_as_sent!
    update!(status: :sent)
  end

  def mark_as_failed!(error_message = nil)
    update!(
      status: :failed,
      metadata: metadata.merge(error: error_message)
    )
  end
end
