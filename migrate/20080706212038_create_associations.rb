class CreateAssociations < ActiveRecord::Migration
  def self.up
    create_table :associations do |t|
      t.references :first, :polymorphic => true
      t.references :second, :polymorphic => true
    end
  end

  def self.down
    drop_table :associations
  end
end
