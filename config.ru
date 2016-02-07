$: << File.expand_path(File.dirname(__FILE__))

APP_LOCATION = (defined?(JRUBY_VERSION) ? File.dirname(__FILE__) + '/' : '') + 'apps/test'
require './app'
run App

module Sequel
    module EmulateOffsetWithRowNumber
        def select_sql
          return super unless emulate_offset_with_row_number?

          offset = @opts[:offset]
          order = @opts[:order]
          if require_offset_order?
            order ||= default_offset_order
            if order.nil? || order.empty?
              raise(Error, "#{db.database_type} requires an order be provided if using an offset")
            end
          end

          # columns = clone(:append_sql=>'', :placeholder_literal_null=>true).columns
          columns = clone(:append_sql=>'', :placeholder_literal_null=>true).get_opts[:select].map do |sel|
            case sel
            when Sequel::SQL::QualifiedIdentifier
                sel.column
            when Sequel::SQL::AliasedExpression
                Sequel::SQL::Identifier.new sel.aliaz
            else
                sel # symbol ?
            end
          end
          dsa1 = dataset_alias(1)
          rn = row_number_column
          sql = @opts[:append_sql] || ''
          subselect_sql_append(sql, unlimited.
            unordered.
            select_append{ROW_NUMBER{}.over(:order=>order).as(rn)}.
            from_self(:alias=>dsa1).
            select(*columns).
            limit(@opts[:limit]).
            where(SQL::Identifier.new(rn) > offset).
            order(rn))
          sql
        end

        def default_offset_order
            model.primary_keys_qualified
        end
    end
end