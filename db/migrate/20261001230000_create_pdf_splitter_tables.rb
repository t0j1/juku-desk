class CreatePdfSplitterTables < ActiveRecord::Migration[8.1]
  def change
    create_table :pdf_split_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :original_filename, null: false
      t.integer :page_count
      t.integer :status, null: false, default: 0
      t.integer :pattern
      t.float   :confidence
      t.jsonb   :boundaries, null: false, default: []
      t.text    :error_message
      t.integer :output_count, null: false, default: 0
      t.timestamps
    end
    add_index :pdf_split_jobs, :status
    add_index :pdf_split_jobs, :created_at

    create_table :pdf_split_page_analyses do |t|
      t.references :pdf_split_job, null: false, foreign_key: { on_delete: :cascade }
      t.integer :page, null: false
      t.string  :raw_text
      t.string  :round_label
      t.string  :section_kind
      t.boolean :is_heading, null: false, default: false
      t.float   :score
      t.timestamps
    end
    add_index :pdf_split_page_analyses, [ :pdf_split_job_id, :page ], unique: true

    create_table :pdf_split_outputs do |t|
      t.references :pdf_split_job, null: false, foreign_key: { on_delete: :cascade }
      t.string  :display_name, null: false
      t.integer :page_from, null: false
      t.integer :page_to, null: false
      t.string  :round_label
      t.string  :section_kind
      t.integer :position, null: false, default: 0
      t.integer :byte_size
      t.timestamps
    end

    create_table :pdf_blobs do |t|
      t.references :pdf_split_job, null: false, foreign_key: { on_delete: :cascade }
      t.references :pdf_split_output, foreign_key: { on_delete: :cascade }
      t.string   :kind, null: false
      t.binary   :data, null: false
      t.integer  :byte_size, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :pdf_blobs, :expires_at
    add_index :pdf_blobs, [ :pdf_split_job_id, :kind ]
  end
end
