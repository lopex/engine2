# coding: utf-8
# frozen_string_literal: true

module Engine2
    module Model
        attr_reader :dummies
        attr_reader :many_to_one_associations, :one_to_many_associations, :many_to_many_associations #, :one_to_one_associations
        attr_reader :after_load_processors, :before_save_processors, :after_save_processors, :before_destroy_processors, :after_destroy_processors
        attr_reader :validation_in_transaction
        attr_reader :properties

        def self.extended cls
            models = cls.db.models
            raise E2Error.new("Model '#{cls.name}' already defined") if models[cls.name.to_sym]
            models[cls.name.to_sym] = cls

            cls.instance_eval do
                @many_to_one_associations = association_reflections.select{|n, a| a[:type] == :many_to_one}
                @one_to_many_associations = association_reflections.select{|n, a| a[:type] == :one_to_many}
                @many_to_many_associations = association_reflections.select{|n, a| a[:type] == :many_to_many}
                # @one_to_one_associations = association_reflections.select{|n, a| a[:type] == :one_to_one}
                @validation_in_transaction = nil
                @after_load_processors = nil
                @before_save_processors = nil
                @after_save_processors = nil
                @around_save_processors = nil
                @before_destroy_processors = nil
                @after_destroy_processors = nil
                @type_info_synchronized = nil
                @model_icon = :"list"
                @model_route = cls.name.to_sym
                @properties = {}
            end
            cls.setup_schema
        end

        def install_processors processors
            hash = {}
            type_info.each_pair do |name, info|
                proc = processors[info[:type]]
                hash[name] = proc if proc
            end
            hash.empty? ? nil : hash
        end

        def setup_schema
            @type_info = {}
            @dummies = []

            type_info do
                schema = @model.db_schema
                @model.primary_keys.each{|pk| (schema[pk]||={})[:primary_key] = true} if @model.primary_key

                schema.each_pair do |name, db_info|
                    @info[name] = {}

                    case db_info[:type]
                    when :integer
                        integer_field name
                    when :string
                        string_field name, case db_info[:db_type]
                        when 'text', 'character varying'
                            100
                        else
                            Integer(db_info[:column_size] || db_info[:db_type][/\((\d+)\)/, 1])
                        end
                    when :time
                        time_field name, LOCS[:default_time_format], LOCS[:default_time_model_format]
                    when :date
                        date_field name, LOCS[:default_date_format], LOCS[:default_date_model_format]
                    when :datetime
                        datetime_field name, LOCS[:default_date_format], LOCS[:default_time_format], LOCS[:default_date_model_format], LOCS[:default_time_model_format]
                    when :decimal
                        size, scale = db_info[:column_size], db_info[:scale].to_i
                        unless size && scale
                            db_info[:db_type] =~ /decimal\((\d+),(\d+)\)/i
                            size, scale = $1.to_i, $2.to_i
                            raise E2Error.new("Cannot parse decimal type for #{db_info}") unless size || scale
                        end
                        decimal_field name, size, scale
                    when :blob
                        blob_field name, 100000
                    when :boolean
                        boolean_field name
                    when :float
                        float_field name
                    when :json, :jsonb
                        json_field name, db_info[:db_type]
                    when nil
                        case db_info[:db_type]
                        when "json", "jsonb"
                            json_field name, db_info[:db_type]
                        else
                            # ignore nil type
                        end
                    else
                        p db_info
                        raise E2Error.new("Unknown column type: #{db_info[:type].inspect} for #{name}")
                    end

                    required name if !db_info[:allow_null]
                    primary_key name if db_info[:primary_key]
                    sequence name, "SEQ_#{@model.table_name}.nextVal" if db_info[:primary_key] && !db_info[:allow_null] && !db_info[:auto_increment] && !@model.natural_key
                    default name, db_info[:ruby_default] if db_info[:ruby_default]
                end

                unique *@model.primary_keys if @model.natural_key && @model.db.adapter_scheme # uri ?

                @model.many_to_one_associations.each do |aname, assoc|
                    many_to_one_field aname
                    decode assoc[:keys].first
                end
            end
        end

        def type_info &blk
            if blk
                raise E2Error.new("type_info already called for model #{self}") if @type_info_synchronized
                TypeInfo.new(self).instance_eval(&blk)
                nil
            else
                @type_info
            end
        end

        def find_type_info name
            model = self
            info = case name
            when Symbol
                model.type_info[name]
            when Sequel::SQL::QualifiedIdentifier
                assoc = model.many_to_one_associations[name.table] || model.many_to_many_associations[name.table]
                raise E2Error.new("Association #{name.table} not found for model #{model}") unless assoc
                assoc.associated_class.type_info[name.column]
            else
                raise E2Error.new("Unknown type info key: #{name} in model #{model}")
            end

            raise E2Error.new("Type info not found for '#{name}' in model '#{model}'") unless info
            info
        end

        def synchronize_type_info
            resolve_dependencies
            verify_associations
            @after_load_processors = install_processors(AfterLoadProcessors)
            @before_save_processors = install_processors(BeforeSaveProcessors)
            @after_save_processors = install_processors(AfterSaveProcessors)
            @around_save_processors = {}
            @before_destroy_processors = install_processors(BeforeDestroyProcessors)
            @after_destroy_processors = install_processors(AfterDestroyProcessors)
            @type_info_synchronized = true
        end

        def resolve_dependencies
            resolved = {}
            @type_info.each_pair do |name, info|
                @validation_in_transaction ||= info[:transaction]
                resolve_dependency(name, resolved)
            end
            @type_info = resolved
        end

        def resolve_dependency name, resolved, seen = []
            seen << name
            deps = @type_info[name][:depends]
            deps.each do |e|
                if !resolved[e]
                    raise E2Error.new("Circular dependency for field '#{name}' in model '#{self}'") if seen.include?(e)
                    resolve_dependency(e, resolved, seen)
                end
            end if deps
            resolved[name] = @type_info[name]
        end

        def verify_associations
            one_to_many_associations.each do |name, assoc|
                other = assoc.associated_class
                other_type_info = other.type_info
                if other_keys = assoc[:keys]
                    other_keys.each do |key|
                        raise E2Error.new("No key '#{key}' found in model '#{other}' being related from #{self}") unless other_type_info[key]
                    end
                end
            end
        end

        attr_reader :scheme_name, :scheme_args

        def scheme s_name = :default, opts = {}, &blk
            @scheme_name = s_name
            @scheme_args = [model_route, self, opts]
            SCHEMES::define_scheme model_route, &blk
        end

        def model_icon icn = nil
            icn ? @model_icon = icn : @model_icon
        end

        def model_route rt = nil
            rt ? @model_route = rt : @model_route
        end
    end

    # def define_dummy_model
    # end

    module MemoryModel
        def self.extended cls
            cls.extend Engine2::Model
            cls.class_eval do
                def save
                end
            end

            def cls.type_info &blk
                if blk
                    super(&blk)
                    @columns = @type_info.keys
                    nil
                else
                    @type_info
                end
            end

        end
    end

    (Validations ||= {}).merge!(
        boolean: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:wrong_boolean_value] if value != info[:true_value] && value != info[:false_value]
        },
        string_length: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:value_exceeds_maximum_length] if value.to_s.length > info[:length]
        },
        date: lambda{|record, field, info|
            value = record.values[field]
            begin
                Sequel.string_to_date(value.to_s)
                nil
            end rescue LOCS[:invalid_date_format]
        },
        time: lambda{|record, field, info|
            value = record.values[field]
            begin
                Sequel.string_to_time(value)
                nil
            end rescue LOCS[:invalid_time_format] unless value.is_a? Integer
        },
        decimal_date: lambda{|record, field, info|
            value = record.values[field].to_s
            if value == '0' && info[:required]
                info[:required][:message]
            else
                Validations[:date].(record, field, info)
            end
        },
        decimal_time: lambda{|record, field, info|
            value = record.values[field].to_s

            if value == '0' && info[:required]
                info[:required][:message]
            else
                LOCS[:invalid_time_format] unless value.rjust(6, '0') =~ info[:model_regexp]
            end

            # value = record.values[field]
            # begin
            #     Sequel.string_to_time("010101 #{value}")
            #     nil
            # end rescue LOCS[:invalid_time_format]
        },

        datetime: lambda{|record, field, info|
            begin
                Sequel.string_to_datetime(record.values[field])
                nil
            end rescue LOCS[:invalid_datetime_format]
        },
        date_range: lambda{|record, field, info|
            to_errors = record.errors[info[:other_date]]
            if to_errors
                record.errors.add(field, *to_errors)
                nil
            else
                from = record.values[field].to_s
                to = record.values[info[:other_date]].to_s
                LOCS[:value_from_gt_to] if Sequel.string_to_date(from) > Sequel.string_to_date(to)
            end
        },
        date_time: lambda{|record, field, info|
            to_errors = record.errors[info[:other_time]]
            if to_errors
                record.errors.add(field, *to_errors)
                nil
            end
        },
        format: lambda{|record, field, info|
            value = record.values[field]
            args = info[:validations][:format]
            args[:message] if value !~ args[:pattern]
        },
        integer: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:invalid_number_value] unless value.is_a?(Integer) || value.to_s =~ /^\-?\d+$/
        },
        float: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:invalid_number_value] unless value.is_a?(Float) # || value.to_s =~ /^\-?\d+$/
        },
        positive_integer: lambda{|record, field, info|
            LOCS[:number_negative] if record.values[field] < 0
        },
        list_select: lambda{|record, field, info|
            value = record.values[field]
            values = info[:values].map(&:first)

            result = if info[:multiselect]
                value.is_a?(Array) && (values - value).length == values.length - value.length
            else
                values.include?(value)
            end
            LOCS[:invalid_list_value] unless result
        },
        decimal: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:invalid_decimal_value] unless value.to_s =~ info[:validations][:decimal][:regexp]
        },
        currency: lambda{|record, field, info|
            value = record.values[field]
            LOCS[:invalid_currency_value] unless value.to_s =~ /^\d+(?:\.\d{,2})?$/
        },
        json: lambda{|record, field, info|
            value = record.values[field]
            begin
                JSON.parse(value)
                nil
            rescue
                "#{LOCS[:invalid_json]}: #{$!.message}"
            end
        },
        unique: lambda{|record, field, info|
            uniq = info[:validations][:unique]
            with = uniq[:with]
            with_errors = with.map{|w|record.errors[w]}
            if with_errors.compact.empty?
                all_fields = [field] + with
                query = all_fields.reduce(record.model.dataset){|ds, f|ds.where f => record[f]}
                query = query.exclude(record.model.primary_keys_hash(record.primary_key_values)) unless record.new?
                unless query.empty?
                    msg = LOCS[:required_unique_value]
                    with.each{|w| record.errors.add(w, msg)} if uniq[:error_with]
                    msg
                end
            else
                nil
            end
        },
        star_to_many_field: lambda{|record, field, info|
            if info[:required]
                if info[:schemes][:star_to_many_field_link] || info[:schemes][:star_to_many_field_create]
                    changes = record[field]
                    added = changes[:link].to_a.length + changes[:create].to_a.length
                    removed = changes[:unlink].to_a.length + changes[:delete].to_a.length
                    info[:required][:message] if (record.new? ? added : (record.send(:"#{field}_dataset").count - removed + added)) == 0
                end
            end
        },
        file_store: lambda{|record, field, info|
            if info[:required]
                files = record[field]
                added = files.count{|f|f[:new]}
                removed = files.count{|f|f[:deleted]}
                referenced = E2Files.db[:files].where(model: record.model.name, field: field.to_s, owner: IdEncoder::join_keys(record.primary_key_values)).count
                info[:required][:message] if (record.new? ? added : referenced - removed + added) == 0
            end
        }
    )

    (AfterLoadProcessors ||= {}).merge!(
        list_select: lambda{|record, field, info|
            value = record[field]
            record[field] = case info[:otype]
            when :string
                 value.split(info[:separator])
            when :integer
                arr = []
                value.bit_length.times{|i| arr << (1 << i) unless value[i].zero?}
                arr
            end if value && info[:multiselect]
        }
    )

    (BeforeSaveProcessors ||= {}).merge!(
        blob_store: lambda{|record, field, info|
            if value = record.values[field] # attachment info
                record.values[info[:name_field]] = value[:name]
                record.values[info[:mime_field]] = value[:mime]
            end
        },
        foreign_blob_store: lambda{|record, field, info|
            if value = record.values[field] # attachment info
                assoc = record.model.association_reflections[info[:assoc_name]]
                blob_model = assoc.associated_class
                file_fields = {info[:bytes_field] => :$data, info[:name_field] => :$name_field, info[:mime_field] => :$mime_field}
                upload = info[:store][:upload]
                file_data = {data: Sequel.blob(open("#{upload}/#{value[:rackname]}", "rb"){|f|f.read}), name_field: value[:name], mime_field: value[:mime]}

                if record.new?
                    statement = blob_model.dataset.prepare(:insert, :insert_blob, file_fields)
                    id = statement.call(file_data)
                    record.values[assoc[:key]] = id
                else
                    key = record.model.naked.select(assoc[:key]).where(record.model.primary_keys_hash(record.primary_key_values)).first
                    statement = blob_model.dataset.where(blob_model.primary_key => :$id_field).prepare(:update, :update_blob, file_fields)
                    statement.call(file_data.merge(id_field: key[assoc[:key]]))
                end
                File.delete("#{upload}/#{value[:rackname]}")
            end
        },
        list_select: lambda{|record, field, info|
            value = record.values[field]
            record[field] = case info[:otype]
            when :string
                value.join(info[:separator])
            when :integer
                value.reduce(0, :|)
            end if value && info[:multiselect] && !info[:dummy]
        }
    )

    (AfterSaveProcessors ||= {}).merge!(
        file_store: lambda{|m, v, info|
            value = m.values[v]
            files = E2Files.db[:files]
            owner = IdEncoder::join_keys(m.primary_key_values)
            upload = info[:store][:upload]
            files_dir = info[:store][:files]
            value.each do |entry|
                name = entry[:name]
                if (rackname = entry[:rackname])
                    unless entry[:deleted]
                        file_id = files.insert(name: name, mime: entry[:mime], owner: owner, model: m.model.name, field: v.to_s, uploaded: Sequel.datetime_class.now)
                        File.rename("#{upload}/#{rackname}", "#{files_dir}/#{name}_#{file_id}")
                    end
                elsif entry[:deleted]
                    File.delete("#{files_dir}/#{name}_#{entry[:id]}")
                    files.where(id: entry[:id]).delete #, model: m.model.table_name.to_s, field: v.to_s
                end
            end if value # .is_a?(Array)
        },
        blob_store: lambda{|record, field, info|
            if value = record.values[field] # attachment info
                upload = info[:store][:upload]
                id = record.model.primary_keys_hash(record.primary_key_values)
                id_n = Hash[record.model.primary_keys.map{|k| [k, :"$#{k}"]}]
                statement = record.model.dataset.where(id_n).prepare(:update, :update_blob, info[:bytes_field] => :$data)
                statement.call(id.merge(data: Sequel.blob(open("#{upload}/#{value[:rackname]}", "rb"){|f|f.read})))
                # record.model.where(id).update(info[:field] => Sequel.blob(open("#{upload}/#{value[:rackname]}", "rb"){|f|f.read}))
                File.delete("#{upload}/#{value[:rackname]}")
            end
        },
    )

    (BeforeDestroyProcessors ||= {}).merge!(
        foreign_blob_store: lambda{|record, field, info|
            assoc = record.model.association_reflections[info[:assoc_name]]
            key = record.model.naked.select(assoc[:key]).where(record.model.primary_keys_hash(record.primary_key_values)).first
            if key
                blob_model = assoc.associated_class
                blob_model.where(blob_model.primary_key => key[assoc[:key]]).delete
            end
        }
    )

    (AfterDestroyProcessors ||= {}).merge!(
        file_store: lambda{|m, v, info|
            files = E2Files.db[:files]
            files_dir = info[:store][:files]
            owner = IdEncoder::join_keys(m.primary_key_values)
            files.select(:id, :name).where(owner: owner, model: m.model.name, field: v.to_s).all.each do |entry|
                File.delete("#{files_dir}/#{entry[:name]}_#{entry[:id]}")
            end
            files.where(owner: owner, model: m.model.name, field: v.to_s).delete
        }
    )

end
