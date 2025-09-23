class CreateAiChatConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_chat_conversations do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, default: 'AI Chat'
      t.jsonb :context, default: {}
      t.timestamps
    end

    add_index :ai_chat_conversations, [:conversation_id, :user_id], unique: true, name: 'idx_ai_chat_conversations_on_conversation_user'
    add_index :ai_chat_conversations, :user_id, name: 'idx_ai_chat_conversations_on_user_id'
  end
end
