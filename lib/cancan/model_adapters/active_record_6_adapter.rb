module CanCan
  module ModelAdapters
    class ActiveRecord6Adapter < ActiveRecord4Adapter
      AbstractAdapter.inherited(self)

      def self.for_class?(model_class)
        ActiveRecord::VERSION::MAJOR == 6 && model_class <= ActiveRecord::Base
      end

      # rails 5 is capable of using strings in enum
      # but often people use symbols in rules
      def self.matches_condition?(subject, name, value)
        return super if Array.wrap(value).all? { |x| x.is_a? Integer }

        attribute = subject.send(name)
        raw_attribute = subject.class.send(name.to_s.pluralize)[attribute]
        !(Array(value).map(&:to_s) & [attribute, raw_attribute]).empty?
      end

      private

      def sanitize_sql(conditions)
        if conditions.is_a?(Hash)
          sanitize_sql_activerecord6(conditions)
        else
          @model_class.send(:sanitize_sql, conditions)
        end
      end

      def sanitize_sql_activerecord6(conditions)
        table = @model_class.send(:arel_table)
        table_metadata = ActiveRecord::TableMetadata.new(@model_class, table)
        predicate_builder = ActiveRecord::PredicateBuilder.new(table_metadata)

        conditions = predicate_builder.resolve_column_aliases(conditions)

        conditions.stringify_keys!

        predicate_builder
          .build_from_hash(conditions)
          .map { |b| visit_nodes(b) }
          .join(' AND ')
      end

      def visit_nodes(node)
        connection = @model_class.send(:connection)
        collector = Arel::Collectors::SubstituteBinds.new(connection, Arel::Collectors::SQLString.new)
        connection.visitor.accept(node, collector).value
      end
    end
  end
end
