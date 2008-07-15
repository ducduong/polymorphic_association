class CreateAssociationTypes < ActiveRecord::Migration
  def self.up
    create_table :association_types do |t|
      t.string :owner, :name
    end
  end

  def self.down
    drop_table :association_types
  end
end
