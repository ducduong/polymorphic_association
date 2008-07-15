require 'ruby-debug'
 
module ActiveRecord
  module Associations
    module PolymorphicAssociation
      
      def self.included base
        base.extend(ClassMethods)
      end
      
      class PolymorphicError < ActiveRecordError
      end
      
      module ClassMethods

        def via_polymorphs(&block)
          [:has_many, :has_one, :has, :belongs_to].each do |macro|
            ClassMethods.send(:define_method, macro) do |association_name, options|
              polymorphic_method(macro, association_name, options)
            end
          end
          
          instance_eval(&block)
          
          [:has_many, :has_one, :has, :belongs_to].each do |macro|
            ClassMethods.send(:remove_method, macro)
          end
        end        
        
        # class User < ActiveRecord::Base
        #   via_polymorphs do
        #     has_many :viewables, :from["people", "projects", "companies""]
        #   end
        # end
        # 
        # The following methods will be created for each instance of User
        # .viewables
        # .viewables.people
        # .viewables.projects
        # .viewables.companies
        def polymorphically_has_many(association_name, options)
          reflection = create_polymorphic_reflection(:has_many, association_name, options, self)
          verify_association(reflection)
          create_methods_for_has_many_association(reflection)
        end
        
        # Basically, in this polymorphic model, has_one and belongs_to are the same
        # because no model holds the id of another model to reference to.
        # We can select whatever marco that describes the logic best
        #
        # class Note < ActiveRecord::Base
        #   via_polymorphs do
        #     belongs_to :container, :from => [:person, :project, :company]
        #     has_one :owner, :from => [:person, :project, :company]
        #   end  
        # end
        # 
        # .container
        # .owner
        def polymorphically_has_one(association_name, options)
          reflection = create_polymorphic_reflection(:has_one, association_name, options, self)
          verify_association(reflection)
          create_methods_for_has_one_association(reflection)
        end
        
        # Another way to create has_many relationship:
        # has :created, :many => :items, :from => [:notes, :contacts, :topics]
        # is similar to
        # has_many :created_items, :from => [:notes, :contacts, :topics]
        def polymorphically_has(action, options)
          verify_existence_of(:many, options)
          verify_pluralization_of(options[:many])
          association_name = action.to_s + "_" + options[:many].to_s
          polymorphically_has_many(association_name, options)
        end

        private
        
        def polymorphic_method(macro, association_name, options)
          case macro
            when :has_many
              polymorphically_has_many(association_name, options)
            when :has
              polymorphically_has(association_name, options)
            when :has_one, :belongs_to
              polymorphically_has_one(association_name, options)  
          end
        end
        
        def create_methods_for_has_many_association(reflection)
          self.send(:define_method, reflection.name) do
            objects = feed_data(self, reflection)
            unless reflection.options[:from].nil?
              reflection.options[:from].each do |plural|
                object_class_name = get_class_name(plural)
                instance_eval("def objects.#{plural}; select {|object| object.is_a?(#{object_class_name})}; end")
              end
            end  
            objects
          end
        end        
        
        def create_methods_for_has_one_association(reflection)
          self.send(:define_method, reflection.name) do
            feed_data(self, reflection).first
          end
          
          self.send(:define_method, "#{reflection.name}=") do |value|
            class_name = value.class.to_s.downcase
            if reflection.options[:from].find{|name| name.to_s == class_name}.nil?
              raise PolymorphicError, "#{reflection.name} cannot be a #{value.class.to_s}"
            end
            feed_data(self, reflection) if @polymorphic_data[reflection.name].nil?
            @polymorphic_data[reflection.name] = [value]
          end
        end   
        
        def verify_pluralization_of(sym)
          sym = sym.to_s
          plural = sym.singularize.pluralize
          raise PolymorphicError, "Plural form is required. You passed :#{sym}. Do you mean #{plural}?" unless sym == plural
        end
        
        def verify_singularization_of(sym)
          sym = sym.to_s
          singular = sym.pluralize.singularize
          raise PolymorphicError, "Singular form is required. You passed :#{sym}. Do you mean #{singular}?" unless sym == singular
        end
        
        def verify_association(reflection)
          if reflection.options[:through].nil? #only verify if it's not a reverse association
            verify_existence_of(:from, reflection.options)
            raise PolymorphicError, ":from option must be an array" unless reflection.options[:from].is_a? Array
          end  
          verify_value_of(:dependent, [:destroy, :none], reflection.options)
          case reflection.macro
            when :has_many
              verify_pluralization_of(reflection.name)
              reflection.options[:from].each{|plural| verify_pluralization_of(plural)} unless reflection.options[:from].nil?
            when :has_one
              verify_singularization_of(reflection.name)
              reflection.options[:from].each{|singular| verify_singularization_of(singular)} unless reflection.options[:from].nil?
          end
        end
        
        def verify_existence_of(option, options)
          raise PolymorphicError, "#{option} is required" unless options[option]
        end
        
        def verify_value_of(option, values, options)
          return if options[option].nil?
          values = values.collect{|v| v.to_s}
          raise PolymorphicError, "#{option} should have value: #{values.to_sentence.to_sentence.sub(", and ", ", or ")}" unless values.include?(options[option].to_s)
        end
        
      end #ClassMethods
       
    end #PolymorphicAssociation
    
  end #Associations
end #ActiveRecord
 
class ActiveRecord::Base
  include ActiveRecord::Associations::PolymorphicAssociation
  include ActiveRecord::Associations::PolymorphicAssociation::Helpers
  
  def after_destroy
    destroy_all_polymorphic_associations_of(self)
  end
  
  def after_save
    save_polymorphic_associations_of(self)
  end
  
end
