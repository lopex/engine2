# coding: utf-8

require 'yaml'
require 'logger'

E2_LIB ||= File.dirname(__FILE__) + "/engine2/"
$LOAD_PATH.unshift(E2_LIB) unless $LOAD_PATH.include?(E2_LIB)

%w[
    core.rb
    handler.rb
    type_info.rb
    model.rb
    templates.rb
    meta.rb
    action.rb
    scheme.rb

    meta/list_meta.rb
    meta/view_meta.rb
    meta/form_meta.rb
    meta/save_meta.rb
    meta/delete_meta.rb
    meta/decode_meta.rb
    meta/link_meta.rb
    meta/infra_meta.rb
].each do |f|
    load f
end

module Engine2
    e2_db_file = (defined? JRUBY_VERSION) ? "jdbc:sqlite:#{APP_LOCATION}/engine2.db" : "sqlite://#{APP_LOCATION}/engine2.db"
    E2DB ||= connect e2_db_file, loggers: [Logger.new($stdout)], convert_types: false, name: :engine2
    DUMMYDB ||= Sequel::Database.new uri: 'dummy'

    if defined? JRUBY_VERSION
        class Sequel::JDBC::Database
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

        module Sequel::JDBC::AS400::DatabaseMethods
            IDENTITY_VAL_LOCAL ||= "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM.SYSDUMMY1".freeze
            def last_insert_id(conn, opts=OPTS)
              statement(conn) do |stmt|
                sql = IDENTITY_VAL_LOCAL
                rs = log_yield(sql){stmt.executeQuery(sql)}
                rs.next
                rs.getInt(1)
              end
            end
        end if defined?(Sequel::JDBC::AS400)
    end

    self.core_loading = false
    # SYNC ||= Mutex.new

    def self.database name
        Object.const_set(name, yield) unless Object.const_defined?(name)
    end

    def self.boot &blk
        @boot_blk = blk
    end

    def self.bootstrap app = APP_LOCATION
        # SYNC.synchronize do
            t = Time.now
            Action.count = 0
            SCHEMES.clear

            load "#{app}/boot.rb"

            Sequel::DATABASES.each &:load_schema_cache_from_file
            load 'models/Files.rb'
            load 'models/UserInfo.rb'
            Dir["#{app}/models/*"].each{|m| load m}
            puts "MODELS, Time: #{Time.now - t}"
            Sequel::DATABASES.each &:dump_schema_cache_to_file

            SCHEMES.merge!
            Engine2.send(:remove_const, :ROOT) if defined? ROOT
            Engine2.const_set(:ROOT, Action.new(nil, :api, DummyMeta, {}))

            @boot_blk.(ROOT)
            ROOT.setup_action_tree
            puts "BOOTSTRAP #{app}, Time: #{Time.new - t}"
        # end
    end

    (FormRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|meta, field, info|
            meta.info[field][:render].merge! true_value: info[:true_value], false_value: info[:false_value]
            meta.info[field][:dont_strip] = info[:dont_strip] if info[:dont_strip]
        },
        date: lambda{|meta, field, info|
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format]
            if date_to = info[:other_date]
                meta.info[field][:render].merge! other_date: date_to #, format: info[:format], model_format: info[:model_format]
                meta.hide_fields date_to
            elsif time = info[:other_time]
                meta.info[field][:render].merge! other_time: time
                meta.hide_fields time
            end
        },
        time: lambda{|meta, field, info|
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format]
        },
        decimal_date: lambda{|meta, field, info|
            FormRendererPostProcessors[:date].(meta, field, info)
            meta.info! field, type: :decimal_date
        },
        decimal_time: lambda{|meta, field, info|
            FormRendererPostProcessors[:time].(meta, field, info)
            meta.info! field, type: :decimal_time
        },
        datetime: lambda{|meta, field, info|
            meta.info[field][:render].merge! date_format: info[:date_format], time_format: info[:time_format], date_model_format: info[:date_model_format], time_model_format: info[:time_model_format]
        },
        # date_range: lambda{|meta, field, info|
        #     meta.info[field][:render].merge! other_date: info[:other_date], format: info[:format], model_format: info[:model_format]
        #     meta.hide_fields info[:other_date]
        #     meta.info[field][:decimal_date] = true if info[:validations][:decimal_date]
        # },
        list_select: lambda{|meta, field, info|
            meta.info[field][:render].merge! list: info[:list]
        },
        many_to_one: lambda{|meta, field, info|
            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = info[:keys]
            field_info[:type] = info[:otype]
            # field_info[:table_loc] = LOCS[info[:assoc_name]]

            (info[:keys] - [field]).each do |of|
                f_info = meta.info.fetch(of)
                f_info[:hidden] = true
                f_info[:type] = meta.assets[:model].type_info[of].fetch(:otype)
            end
        },
        file_store: lambda{|meta, field, info|
            meta.info[field][:render].merge! multiple: info[:multiple]
            # meta[:model] = meta.action.model.table_name
        },
        star_to_many: lambda{|meta, field, info|
            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            # meta.info[field][:render].merge! multiple: info[:multiple]
            # field_info = meta.info[field]
            # field_info[:resource] ||= "#{Handler::API}#{meta.model.namespace}/#{info[:assoc_name]}"
        }
    )

    (ListRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|meta, field, info|
            meta.info! field, type: :boolean # move to meta ?
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! true_value: info[:true_value], false_value: info[:false_value]
        },
        list_select: lambda{|meta, field, info|
            meta.info! field, type: :list_select
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! list: info[:list]
        },
        datetime: lambda{|meta, field, info|
            meta.info! field, type: :datetime
        },
        decimal_date: lambda{|meta, field, info|
            meta.info! field, type: :decimal_date
        },
        decimal_time: lambda{|meta, field, info|
            meta.info! field, type: :decimal_time
        },
        # date_range: lambda{|meta, field, info|
        #     meta.info[field][:type] = :decimal_date if info[:validations][:decimal_date] # ? :decimal_date : :date
        # }
    )

    (SearchRendererPostProcessors ||= {}).merge!(
        many_to_one: lambda{|meta, field, info|
            model = meta.assets[:model]
            if model.type_info[field]
                keys = info[:keys]
            else
                meta.check_static_meta
                model = Object.const_get(model.many_to_one_associations[field[/^\w+?(?=__)/].to_sym][:class_name])
                # meta.action.define_action :"#{info[:assoc_name]}!" do # assoc_#{aname}
                #     define_action :decode, DecodeEntryMeta, assoc: model.association_reflections[info[:assoc_name]] do
                #         run_scheme :default_many_to_one
                #     end
                # end

                # verify associations ?
                # model = Model.models.fetch(field[/^\w+?(?=__)/].to_sym)
                keys = info[:keys].map{|k| :"#{model.table_name}__#{k}"}
            end

            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = keys
            field_info[:type] = info[:otype]
            # field_info[:table_loc] = LOCS[info[:assoc_name]]

            (keys - [field]).each do |of|
                f_info = meta.info[of]
                raise E2Error.new("Missing searchable field: '#{of}' in model '#{meta.assets[:model]}'") unless f_info
                f_info[:hidden_search] = true
                f_info[:type] = model.type_info[of].fetch(:otype)
            end
        },
        date: lambda{|meta, field, info|
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format] # Model::DEFAULT_DATE_FORMAT
        },
        decimal_date: lambda{|meta, field, info|
            SearchRendererPostProcessors[:date].(meta, field, info)
        }
    )

    (DefaultFormRenderers ||= {}).merge!(
        date: lambda{|meta, info|
            info[:other_date] ? Templates.date_range : (info[:other_time] ? Templates.date_time : Templates.date_picker)

        },
        time: lambda{|meta, info| Templates.time_picker},
        datetime: lambda{|meta, info| Templates.datetime_picker},
        file_store: lambda{|meta, info| Templates.file_store},
        blob: lambda{|meta, info| Templates.blob}, # !!!
        blob_store: lambda{|meta, info| Templates.blob},
        foreign_blob_store: lambda{|meta, info| Templates.blob},
        string: lambda{|meta, info| Templates.input_text(info[:length])},
        text: lambda{|meta, info| Templates.text},
        integer: lambda{|meta, info| Templates.integer},
        decimal: lambda{|meta, info| Templates.decimal},
        decimal_date: lambda{|meta, info| DefaultFormRenderers[:date].(meta, info)},
        decimal_time: lambda{|meta, info| Templates.time_picker},
        email: lambda{|meta, info| Templates.email(info[:length])},
        password: lambda{|meta, info| Templates.password(info[:length])},
        # date_range: lambda{|meta, info| Templates.date_range},
        boolean: lambda{|meta, info| Templates.checkbox_buttons(optional: !info[:required])},
        currency: lambda{|meta, info| Templates.currency},
        list_select: lambda{|meta, info|
            length = info[:list].length
            if length <= 3
                Templates.list_buttons(optional: !info[:required])
            elsif length <= 15
                max_length = info[:list].max_by{|a|a.last.length}.last.length
                Templates.list_bsselect(max_length, optional: !info[:required])
            else
                max_length = info[:list].max_by{|a|a.last.length}.last.length
                Templates.list_select(max_length, optional: !info[:required])
            end
        },
        star_to_many: lambda{|meta, info| Templates.scaffold},
        many_to_one: lambda{|meta, info| # Templates.scaffold_picker
            tmpl_type = info[:decode][:form]
            case
            when tmpl_type[:scaffold]; Templates.scaffold_picker
            when tmpl_type[:list];     Templates.bsselect_picker
            when tmpl_type[:typeahead];Templates.typeahead_picker
            else
                raise E2Error.new("Unknown decode type #{tmpl_type}")
            end
        }, # required/opt
    )

    (DefaultSearchRenderers ||= {}).merge!(
        date: lambda{|meta, info| SearchTemplates.date_range},
        decimal_date: lambda{|meta, info| SearchTemplates.date_range},
        integer: lambda{|meta, info| SearchTemplates.integer_range},
        string: lambda{|meta, info| SearchTemplates.input_text},
        boolean: lambda{|meta, info| SearchTemplates.checkbox_buttons},
        list_select: lambda{|meta, info|
            length = info[:list].length
            if length <= 3
                SearchTemplates.list_buttons
            elsif length <= 15
                # max_length = info[:list].max_by{|a|a.last.length}.last.length
                SearchTemplates.list_bsselect(multiple: info[:multiple])
            else
                # max_length = info[:list].max_by{|a|a.last.length}.last.length
                SearchTemplates.list_select
            end
        },
        many_to_one: lambda{|meta, info|
            tmpl_type = info[:decode][:search]
            case
            when tmpl_type[:scaffold]; SearchTemplates.scaffold_picker(multiple: tmpl_type[:multiple])
            when tmpl_type[:list];     SearchTemplates.bsselect_picker(multiple: tmpl_type[:multiple])
            when tmpl_type[:typeahead];SearchTemplates.typeahead_picker
            else
                raise E2Error.new("Unknown decode type #{tmpl_type}")
            end
        }
    )

    (DefaultFilters ||= {}).merge!(
        string: lambda{|query, name, value, type_info, hash|
            case type_info[:type]
            when :many_to_one
                query.where(name => value)
            else
                query.where(name.like("%#{value}%"))
            end
        },
        date: lambda{|query, name, value, type_info, hash|
            if value.is_a? Hash
                from, to = value[:from], value[:to]
                if from && to
                    query.where(name => from .. to)
                elsif from
                    query.where(name >= Sequel.string_to_date(from))
                elsif to
                    query.where(name <= Sequel.string_to_date(to))
                else
                    query # ?
                end
            else
                query.where(name => Sequel.string_to_date(value))
            end
        },
        integer: lambda{|query, name, value, type_info, hash|
            if value.is_a? Hash
                from, to = value[:from], value[:to]
                if from && to
                    query.where(name => from .. to)
                else
                    query.where(from ? name >= from.to_i : name <= to.to_i)
                end
            elsif value.is_a? Integer
                query.where(name => value)
            elsif value.is_a? Array
                if !value.empty?
                    case type_info[:type]
                    when :many_to_one
                        keys = type_info[:keys]
                        if keys.length == 1
                            query.where(name => value)
                        else
                            query.where(keys.map{|k| hash[k]}.transpose.map{|vals| Hash[keys.zip(vals)]}.inject{|q, c| q | c
                            })
                        end
                    when :list_select
                        query.where(name => value) # decode in sql query ?
                    when :integer
                        query
                    else
                        nil
                    end
                else
                    nil
                end
            else
                nil
            end
        }
    )

end