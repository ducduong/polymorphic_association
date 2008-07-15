class AssociationLinking < ActiveRecord::Base
  belongs_to :association_types
  belongs_to :associations
end
