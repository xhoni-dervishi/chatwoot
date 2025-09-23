# == Schema Information
#
# Table name: ai_chat_messages
#
#  id                      :bigint           not null, primary key
#  content                 :text             not null
#  metadata                :jsonb
#  role                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  ai_chat_conversation_id :bigint           not null
#
# Indexes
#
#  idx_ai_chat_messages_on_conversation_created       (ai_chat_conversation_id,created_at)
#  idx_ai_chat_messages_on_conversation_id            (ai_chat_conversation_id)
#  index_ai_chat_messages_on_ai_chat_conversation_id  (ai_chat_conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (ai_chat_conversation_id => ai_chat_conversations.id)
#
class AiChatMessage < ApplicationRecord
  belongs_to :ai_chat_conversation

  validates :role, presence: true, inclusion: { in: %w[user assistant] }
  validates :content, presence: true

  scope :user_messages, -> { where(role: 'user') }
  scope :assistant_messages, -> { where(role: 'assistant') }
  scope :recent, -> { order(:created_at) }

  def user_message?
    role == 'user'
  end

  def assistant_message?
    role == 'assistant'
  end
end
