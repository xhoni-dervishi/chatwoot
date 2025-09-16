class AddAiConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_conversations do |t|
      t.references :conversation, null: false, foreign_key: true
      t.boolean :ai_enabled, default: false
      t.jsonb :ai_config, default: {}
      t.timestamps
    end

    add_index :ai_conversations, :conversation_id, unique: true, name: 'idx_ai_conversations_on_conversation_id'
    add_index :ai_conversations, :ai_enabled, name: 'idx_ai_conversations_on_ai_enabled'
  end
end
