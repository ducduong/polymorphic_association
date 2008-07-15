module ActiveRecord
  module Reflection
    
    module ClassMethods
  
      def create_polymorphic_reflection(macro, name, options, active_record)
        reflection = PolymorphicReflection.new(macro, name, options, active_record)
        write_inheritable_hash :reflections, name => reflection
        reflection
      end

      def polymorphic_reflections
        reflections.values.select { |reflection| reflection.is_a?(PolymorphicReflection) }
      end
      
    end
 
    class PolymorphicError < ActiveRecordError
    end
    
    class PolymorphicReflection < MacroReflection
      #def initialize(macro, name, options, active_record)
      #  @association_type ||= AssociationType.find_or_create_by_name_and_owner(name.to_s, active_record.to_s)
      #  super(macro, name, options, active_record)
      #end
      def association_type
        @association_type ||= AssociationType.find_or_create_by_name_and_owner(@name.to_s, @active_record.to_s)
      end
      
      def is_reverse_association?
        @options[:through].nil? == false
      end
    end
 
  end
end
