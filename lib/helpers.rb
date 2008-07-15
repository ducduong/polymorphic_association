module ActiveRecord
  module Associations
    module PolymorphicAssociation
      module Helpers
        
        private
        
        # Although just one value is needed. We return an array of one item
        # The reason is we can clone array (deep copy), and then compare original data with current data of the active record
        # It's used to specify which objects have been added to or removed from the dependents list in order to update associations correctly
        def get_object_through_has_one_association(owner, reflection)
          #TODO cached
          
          association = get_associations_for_object(owner, reflection)[0]
          
          return [] if association.nil?
          
          if association.first_type.to_s == owner.class.to_s 
            [association.second_type.constantize.find(association.second_id)]
          else
            [association.first_type.constantize.find(association.first_id)]
          end
        end
        
        def get_objects_through_has_many_association(owner, reflection)
          
          # TODO: implement cached

          associations = get_associations_for_object(owner, reflection)
          puts associations if reflection.is_reverse_association?
          return [] if associations == []
          
          objects = []
          
          object_class_names = []

          unless reflection.options[:from].nil?
            object_class_names = reflection.options[:from].collect {|object| get_class_name(object)}
          else
            object_class_names = (associations.collect {|a| a.first_type} + associations.collect {|a| a.second_type}).uniq
            object_class_names = object_class_names - [owner.class.to_s]
            puts object_class_names
          end
          
          object_class_names.each do |object_class_name|
            
            if object_class_name < owner.class.to_s 
              ids = associations.select{|i| i.first_type == object_class_name}.collect{|i| i.first_id.to_i}
            else
              ids = associations.select{|i| i.second_type == object_class_name}.collect{|i| i.second_id.to_i}
            end
            
            objects.concat(object_class_name.constantize.find(:all, :conditions => ['id in (?)', ids]))
          end
              
          objects
        end
        
        def get_all_associations_for(object)
          sql_finder = <<-EOS
            SELECT * FROM associations
            WHERE ((first_type = ? AND first_id = ?) OR (second_type = ? AND second_id = ?))
          EOS
          
          Association.find_by_sql([sql_finder,
                          object.class.to_s, object.id.to_s, 
                          object.class.to_s, object.id.to_s])
        end
        
        def get_associations_for_object(object, reflection)
          if reflection.is_reverse_association?
            compare = "<>"
            association_name = reflection.options[:through].to_s
          else
            compare = "="
            association_name = reflection.name.to_s
          end
          
          sql_finder = <<-EOS
            SELECT a.* FROM associations AS a
            INNER JOIN association_linkings AS l ON l.association_id = a.id
            INNER JOIN association_types AS t ON l.association_type_id = t.id
            WHERE t.owner #{compare} ? AND t.name = ? AND 
                  ((a.first_type = ? AND a.first_id = ?) OR (a.second_type = ? AND a.second_id = ?))
          EOS

          Association.find_by_sql([sql_finder,
                          object.class.to_s, association_name,
                          object.class.to_s, object.id.to_s, 
                          object.class.to_s, object.id.to_s])
        end
        
        # @polymorphic_data holds the current association information for the active record
        # @polymorphic_original_data holds the original association information for the active record
        # when the active record is saved, the too hash will be compared to add or destroy appropriate associations
        def feed_data(owner, reflection)
          
          @polymorphic_data ||= {}
          #if it is called the first time, we need to load it from database and set original data
          if @polymorphic_data[reflection.name].nil?
            reverse = reflection.options[:through].nil? == false
            case reflection.macro
              when :has_many
                data = get_objects_through_has_many_association(owner, reflection)
              when :has_one
                data = get_object_through_has_one_association(owner, reflection)
            end
            @polymorphic_original_data ||= {}
            @polymorphic_data[reflection.name] = data
            @polymorphic_original_data[reflection.name] = data.clone
          end
          @polymorphic_data[reflection.name]
        end
        
        def destroy_all_polymorphic_associations_of(object)
          return if ["Association", "AssociationLinking","AssociationType"].include?(object.class)
          
          @polymorphic_data ||= {}
          dependents_to_destroy = []
                    
          self.class.polymorphic_reflections.each do |reflection|
            if reflection.options[:dependent].to_s == "destroy"
              feed_data(self, reflection) if @polymorphic_data[reflection.name].nil?
              @polymorphic_data[reflection.name].each do |dependent|
                dependents_to_destroy << dependent
              end
            end
          end
          
          # delete associations related to this object
          associations = get_all_associations_for(object)
          association_ids = associations.collect{|a| a.id}
          Association.delete_all(["id in (?)", association_ids])
          AssociationLinking.delete_all(["association_id in (?)", association_ids])
          
          #TODO
          # CONSIDERING
          # has_many :guests, :from => [:dogs, :cats], :dependent => :destroy_dogs
          # all guest dogs will be deleted

          dependents_to_destroy.each do |dependent|
            dependent.destroy
          end          
                    
          #TODO clear all related caches 
        end
        
        def save_polymorphic_associations_of(object)
          @polymorphic_data ||= {}
          @polymorphic_original_data ||= {}
          object.class.polymorphic_reflections.each do |reflection|
            if @polymorphic_data[reflection.name] != @polymorphic_original_data[reflection.name]
              create_and_destroy_polymorphic_associations_of(object, reflection)
            end
          end
        end
        
        def create_and_destroy_polymorphic_associations_of(object, reflection) 
          dependents_to_create = @polymorphic_data[reflection.name] - @polymorphic_original_data[reflection.name]
          dependents_to_destroy = @polymorphic_original_data[reflection.name] - @polymorphic_data[reflection.name]
          # reset original data after saving
          @polymorphic_original_data[reflection.name] = @polymorphic_data[reflection.name].clone
          create_polymorphic_associations_for(object, dependents_to_create.compact, reflection)
          destroy_polymorphic_associations_of(object, dependents_to_destroy.compact, reflection)
        end
        
        def create_polymorphic_associations_for(object, dependents, reflection)
          #TODO update cache
          #TODO handle reverse association
          
          return if dependents.empty?
          
          associations = get_associations_for_object(object, reflection)
          dependents.each do |dependent|
            verify_dependent_type(dependent, reflection)
            if object.class.to_s < dependent.class.to_s
              association = associations.find{|a| a.second_type.to_s==dependent.class.to_s and a.second_id==dependent.id}
              association ||= Association.create do |a|
                a.first_type, a.first_id, a.second_type, a.second_id = object.class.to_s, object.id, dependent.class.to_s, dependent.id
              end
            else
              association = associations.find{|a| a.first_type.to_s==dependent.class.to_s and a.first_id==dependent.id}
              association ||= Association.create do |a|
                a.first_type, a.first_id, a.second_type, a.second_id = dependent.class.to_s, dependent.id, object.class.to_s, object.id
              end
            end
            association.association_linkings.create(:association_type_id => reflection.association_type.id)
          end
        end
        
        def destroy_polymorphic_associations_of(object, dependents, reflection)
          #TODO update cache
          
          return if dependents.empty?
          all_associations = get_associations_for_object(object, reflection)
          associations_to_destroy = []
          dependents.each do |dependent|
            associations_to_destroy << all_associations.find{|a| (a.first_type.to_s==dependent.class.to_s and a.first_id==dependent.id) or
                                                                 (a.second_type.to_s==dependent.class.to_s and a.second_id==dependent.id)}
          end
          association_ids_to_destroy = associations_to_destroy.collect{|a| a.id}
          Association.delete_all(["id in (?)", association_ids_to_destroy])
          AssociationLinking.delete_all(["association_id in (?)", association_ids_to_destroy])
        end
        
        def verify_dependent_type(dependent, reflection)
          if reflection.options[:from].find{|f| get_class_name(f) == dependent.class.to_s}.nil?
            raise ActiveRecord::Associations::PolymorphicAssociation::PolymorphicError, "#{dependent.class} cannot be added to #{self.class}.#{reflection.name}."
          end
        end
        
        def self.get_class_name(sym)
          sym.to_s.singularize.capitalize
        end
        
        def get_class_name(sym)
          sym.to_s.singularize.capitalize
        end
      end
    end
  end
end
