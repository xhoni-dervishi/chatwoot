class CreateScheduledFollowUps < ActiveRecord::Migration[7.1]
  def change
    create_table :scheduled_follow_ups do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :message_content, null: false
      t.datetime :scheduled_at, null: false
      t.integer :status, default: 0, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :scheduled_follow_ups, [:conversation_id, :scheduled_at]
    add_index :scheduled_follow_ups, [:status, :scheduled_at]
    add_index :scheduled_follow_ups, :metadata, using: :gin
  end
end

