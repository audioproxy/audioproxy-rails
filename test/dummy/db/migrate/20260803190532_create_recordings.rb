class CreateRecordings < ActiveRecord::Migration[8.1]
  def change
    create_table :recordings do |t|
      t.string :title

      t.timestamps
    end
  end
end
