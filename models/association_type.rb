class AssociationType < ActiveRecord::Base
  has_many :association_linkings
  has_many :associations, :through => :association_linkings
end
