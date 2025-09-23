class CreateAiChatMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_chat_messages do |t|
      t.references :ai_chat_conversation, null: false, foreign_key: true
      t.string :role, null: false # 'user' or 'assistant'
      t.text :content, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_chat_messages, :ai_chat_conversation_id, name: 'idx_ai_chat_messages_on_conversation_id'
    add_index :ai_chat_messages, [:ai_chat_conversation_id, :created_at], name: 'idx_ai_chat_messages_on_conversation_created'
  end
end
