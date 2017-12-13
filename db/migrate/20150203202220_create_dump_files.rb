class CreateDumpFiles < ActiveRecord::Migration[4.2]
  def change
    create_table :dump_files do |t|
      t.belongs_to :dump, index: true
      t.string :path
      t.string :md5

      t.timestamps null: false
    end
    # add_foreign_key :dump_files, :dumps
  end
end
