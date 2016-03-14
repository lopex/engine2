$: << File.expand_path(File.dirname(__FILE__))

APP_LOCATION = (defined?(JRUBY_VERSION) ? File.dirname(__FILE__) + '/' : '') + 'apps/test'
require './app'
run App
Engine2.bootstrap

module Sequel
    module SequelFixes
        def self.fix_aliased_expression ds
            ds.get_opts[:select].map do |sel|
                case sel
                when Sequel::SQL::QualifiedIdentifier
                    sel.column
                when Sequel::SQL::AliasedExpression
                    Sequel::SQL::Identifier.new sel.aliaz
                else
                    sel # symbol ?
                end
            end
        end
    end

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
          columns = SequelFixes.fix_aliased_expression(clone(:append_sql=>'', :placeholder_literal_null=>true))
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

    module Oracle::DatasetMethods
        def select_sql
          return super if @opts[:sql]
          if o = @opts[:offset]
            # columns = clone(:append_sql=>String.new, :placeholder_literal_null=>true).columns
            columns = SequelFixes.fix_aliased_expression(clone(:append_sql=>String.new, :placeholder_literal_null=>true))
            dsa1 = dataset_alias(1)
            rn = row_number_column
            limit = @opts[:limit]
            ds = unlimited.
              from_self(:alias=>dsa1).
              select_append(ROW_NUMBER_EXPRESSION.as(rn)).
              from_self(:alias=>dsa1).
              select(*columns).
              where(SQL::Identifier.new(rn) > o)
            ds = ds.where(SQL::Identifier.new(rn) <= Sequel.+(o, limit)) if limit
            sql = @opts[:append_sql] || String.new
            subselect_sql_append(sql, ds)
            sql
          elsif limit = @opts[:limit]
            ds = clone(:limit=>nil)
            # Lock doesn't work in subselects, so don't use a subselect when locking.
            # Don't use a subselect if custom SQL is used, as it breaks somethings.
            ds = ds.from_self unless @opts[:lock]
            sql = @opts[:append_sql] || String.new
            subselect_sql_append(sql, ds.where(SQL::ComplexExpression.new(:<=, ROW_NUMBER_EXPRESSION, limit)))
            sql
          else
            super
          end
        end
    end if defined? Oracle
end