# == Schema Information
#
# Table name: ai_conversations
#
#  id              :bigint           not null, primary key
#  ai_config       :jsonb
#  ai_enabled      :boolean          default(FALSE)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#
# Indexes
#
#  idx_ai_conversations_on_ai_enabled         (ai_enabled)
#  idx_ai_conversations_on_conversation_id    (conversation_id) UNIQUE
#  index_ai_conversations_on_conversation_id  (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#
class AiConversation < ApplicationRecord
  belongs_to :conversation

  validates :conversation_id, presence: true, uniqueness: true

  scope :enabled, -> { where(ai_enabled: true) }

  def enable_ai!
    update!(ai_enabled: true)
  end

  def disable_ai!
    update!(ai_enabled: false)
  end
end
