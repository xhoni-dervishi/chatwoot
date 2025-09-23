# == Schema Information
#
# Table name: ai_chat_conversations
#
#  id              :bigint           not null, primary key
#  context         :jsonb
#  title           :string           default("AI Chat"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_ai_chat_conversations_on_conversation_user  (conversation_id,user_id) UNIQUE
#  idx_ai_chat_conversations_on_user_id            (user_id)
#  index_ai_chat_conversations_on_conversation_id  (conversation_id)
#  index_ai_chat_conversations_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (user_id => users.id)
#
class AiChatConversation < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  has_many :ai_chat_messages, dependent: :destroy

  validates :conversation_id, presence: true
  validates :user_id, presence: true
  validates :title, presence: true
  validates :conversation_id, uniqueness: { scope: :user_id }

  scope :for_user, ->(user) { where(user: user) }
  scope :for_conversation, ->(conversation) { where(conversation: conversation) }

  def add_message(role:, content:, metadata: {})
    ai_chat_messages.create!(
      role: role,
      content: content,
      metadata: metadata
    )
  end

  def last_message
    ai_chat_messages.order(:created_at).last
  end

  def message_count
    ai_chat_messages.count
  end

  def conversation_context
    @conversation_context ||= Ai::ConversationContextService.new(conversation).build_context
  end

  def build_ai_messages
    # Include conversation context + chat history
    conversation_context + ai_chat_messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content
      }
    end
  end
end
