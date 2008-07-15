class Association < ActiveRecord::Base
  has_many :association_linkings
  has_many :association_types, :through => :association_linkings

end
