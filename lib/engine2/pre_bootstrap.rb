# coding: utf-8
# frozen_string_literal: true

module Sequel
    class JDBC::Database
        def metadata_schema_and_table(table, opts)
            im = input_identifier_meth(opts[:dataset])
            schema, table = schema_and_table(table)
            schema ||= default_schema
            schema ||= opts[:schema]
            schema = im.call(schema) if schema
            table = im.call(table)
            [schema, table]
        end
    end

    module JDBC::AS400::DatabaseMethods
        IDENTITY_VAL_LOCAL ||= "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM.SYSDUMMY1".freeze
        def last_insert_id(conn, opts=OPTS)
          statement(conn) do |stmt|
            sql = IDENTITY_VAL_LOCAL
            rs = log_yield(sql){stmt.executeQuery(sql)}
            rs.next
            rs.getInt(1)
          end
        end

        def valid_connection_sql
            'select 1 from sysibm.sysdummy1'
        end
    end if defined?(JDBC::AS400)

    class JDBC::AS400::Dataset
        def supports_where_true?
            false
        end
    end if defined?(JDBC::AS400)

    module SchemaCaching
      def load_schema_cache(file)
        @schemas = Marshal.load(File.read(file, mode: 'rb'))
        nil
      end
    end

end if defined? JRUBY_VERSION
