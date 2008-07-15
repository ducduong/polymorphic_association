class CreateAssociationLinkings < ActiveRecord::Migration
  def self.up
    create_table :association_linkings do |t|
      t.integer :association_id, :association_type_id
    end
  end

  def self.down
    drop_table :association_linkings
  end
end
