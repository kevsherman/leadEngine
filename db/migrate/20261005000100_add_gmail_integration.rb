class AddGmailIntegration < ActiveRecord::Migration[8.1]
  def change
    create_table :gmail_connections do |t|
      t.string :mailbox, null: false
      t.string :client_id
      t.text :client_secret
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.string :status, default: "needs_authorization", null: false
      t.boolean :polling_enabled, default: false, null: false
      t.boolean :sending_enabled, default: false, null: false
      t.boolean :alias_confirmed, default: false, null: false
      t.datetime :alias_verified_at
      t.integer :authorization_version, default: 0, null: false
      t.integer :poll_interval_seconds, default: 60, null: false
      t.string :shopify_senders, default: "mailer@shopify.com", null: false
      t.date :import_since, null: false
      t.string :history_id
      t.datetime :last_attempt_at
      t.datetime :last_synced_at
      t.string :last_error
      t.timestamps
    end
    add_index :gmail_connections, :mailbox, unique: true
    add_reference :conversations, :gmail_connection, foreign_key: true
    add_column :conversations, :email_provider, :string, default: "fake", null: false
    add_column :conversations, :gmail_thread_id, :string
    add_index :conversations, [ :gmail_connection_id, :gmail_thread_id ]
    remove_index :email_drafts, :conversation_id
    add_index :email_drafts, :conversation_id
    add_column :email_drafts, :approval_provider, :string
    add_column :email_drafts, :approval_connection_version, :integer
    add_reference :messages, :gmail_connection, foreign_key: true
    add_column :messages, :provider_thread_id, :string
    add_column :messages, :rfc_message_id, :string
    add_column :messages, :reply_to, :string
    add_column :messages, :cc, :string
    add_column :messages, :references_header, :jsonb, default: [], null: false
    add_column :messages, :attachments, :jsonb, default: [], null: false
    add_index :messages, [ :gmail_connection_id, :rfc_message_id ]
    add_column :send_operations, :provider, :string, default: "fake", null: false
    add_reference :send_operations, :gmail_connection, foreign_key: true
    add_column :send_operations, :authorization_version, :integer
    add_column :send_operations, :rfc_message_id, :string
    add_column :send_operations, :provider_message_id, :string
    add_column :send_operations, :provider_thread_id, :string
    add_column :send_operations, :requested_by_id, :bigint
    add_foreign_key :send_operations, :operators, column: :requested_by_id
    add_index :send_operations, :rfc_message_id, unique: true
    create_table :gmail_review_items do |t|
      t.references :gmail_connection, null: false, foreign_key: true
      t.string :provider_message_id, null: false
      t.string :thread_id, null: false
      t.string :reason, null: false
      t.boolean :resolved, default: false, null: false
      t.timestamps
    end
    add_index :gmail_review_items, [ :gmail_connection_id, :provider_message_id ], unique: true, name: "index_gmail_reviews_on_connection_message"
  end
end
