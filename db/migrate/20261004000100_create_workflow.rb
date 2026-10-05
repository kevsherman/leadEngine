class CreateWorkflow < ActiveRecord::Migration[8.1]
  def change
    create_table :operators do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :operators, :email, unique: true
    create_table :conversations do |t|
      t.string :source_id, null: false
      t.string :customer_name, null: false
      t.string :customer_email, null: false
      t.string :subject, null: false
      t.string :project
      t.string :category
      t.string :language, default: "English", null: false
      t.string :status, default: "needs_review", null: false
      t.string :next_action, null: false
      t.jsonb :known_fields, default: {}, null: false
      t.jsonb :missing_fields, default: [], null: false
      t.datetime :last_activity_at, null: false
      t.timestamps
    end
    add_index :conversations, :source_id, unique: true
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :provider_id, null: false
      t.string :direction, null: false
      t.string :sender, null: false
      t.string :recipient
      t.string :subject, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :messages, :provider_id, unique: true
    create_table :email_drafts do |t|
      t.references :conversation, null: false, foreign_key: true, index: { unique: true }
      t.string :to, null: false
      t.string :cc
      t.string :subject, null: false
      t.text :body, null: false
      t.string :status, default: "editing", null: false
      t.integer :lock_version, default: 0, null: false
      t.references :approved_by, foreign_key: { to_table: :operators }
      t.references :approved_message, foreign_key: { to_table: :messages }
      t.datetime :approved_at
      t.timestamps
    end
    create_table :send_operations do |t|
      t.references :email_draft, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false
      t.jsonb :payload, null: false
      t.string :error
      t.timestamps
    end
    create_table :fake_deliveries do |t|
      t.references :send_operation, null: false, foreign_key: true, index: { unique: true }
      t.string :provider_message_id, null: false
      t.jsonb :payload, null: false
      t.timestamps
    end
    add_index :fake_deliveries, :provider_message_id, unique: true
    create_table :audit_events do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :operator, foreign_key: true
      t.string :action, null: false
      t.text :details
      t.timestamps
    end
  end
end
