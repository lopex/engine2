# coding: utf-8
# frozen_string_literal: true

module Engine2
    class TypeInfo
        def initialize model
            @model = model
            @info = model.type_info
        end

        def define_field field, type
            info = @info[field]
            raise E2Error.new("Field '#{field}' already defined in model '#{@model}'") if info && info[:type]

            unless info
                @info[field] = info = {dummy: true}
                @model.dummies << field
            end

            info.merge!({
                name: field,
                otype: type,
                type: type,
                validations: {}
            })
            yield info
        end

        def modify_field field
            info = @info[field]
            raise E2Error.new("No field '#{field}' defined for model '#{@model}'") unless info
            yield info
        end

        def depends_on what, *on
            modify_field what do |info|
                (info[:depends] ||= []).concat(on)
            end
        end

        def null_value field, value
            modify_field field do |info|
                info[:null_value] = value
            end
        end

        def any_field field
            define_field field, :any do |info|
            end
        end

        def string_field field, length
            define_field field, :string do |info|
                info[:length] = length
                info[:validations][:string_length] = true
            end
        end

        def blob_field field, length
            define_field field, :blob do |info|
                info[:length] = length
            end
        end

        def integer_field field
            define_field field, :integer do |info|
                info[:validations][:integer] = true
            end
        end

        def boolean_field field
            define_field field, :boolean do |info|
            end
        end

        def boolean field, true_value = true, false_value = false
            modify_field field do |info|
                info[:type] = :boolean
                info[:true_value] = true_value
                info[:false_value] = false_value
                info[:validations][:boolean] = true
            end
        end

        def date_field field, format, model_format
            define_field field, :date do |info|
                info[:format] = format
                info[:model_format] = model_format
                info[:validations][:date] = true
            end
        end

        def time_field field, format, model_format
            define_field field, :time do |info|
            end
            time field, format, model_format
        end

        def time field, format, model_format
            modify_field field do |info|
                info[:type] = :time
                info[:format] = format
                info[:model_format] = model_format
                info[:validations][:time] = true
            end
        end

        def datetime_field field, date_format, time_format, date_model_format, time_model_format
            define_field field, :datetime do |info|
                info[:date_format] = date_format
                info[:time_format] = time_format
                info[:date_model_format] = date_model_format
                info[:time_model_format] = time_model_format
                info[:validations][:datetime] = true
            end
        end

        def decimal_field field, size, scale
            define_field field, :decimal do |info|
                info[:validations][:decimal] = {
                    scale: scale,
                    size: size,
                    regexp: (scale && size) ? /^\d{,#{size - scale}}(?:\.\d{,#{scale}})?$/ : nil
                }
            end
        end

        def text_field field
            define_field field, :text do |info|
            end
        end

        def decimal_date field, format = LOCS[:default_date_format], model_format = "yyyyMMdd"
            modify_field field do |info|
                info[:type] = :decimal_date
                info[:format] = format
                info[:model_format] = model_format
                info[:validations][:decimal_date] = true
            end
        end

        def decimal_time field, format = LOCS[:default_time_format], model_format = "HHmmss", model_regexp = /^(\d{2})(\d{2})(\d{2})$/
            modify_field field do |info|
                info[:type] = :decimal_time
                info[:format] = format
                info[:model_format] = model_format
                info[:model_regexp] = model_regexp
                info[:validations][:decimal_time] = true
            end
        end

        def default field, value
            modify_field field do |info|
                info[:default] = value
            end
        end

        def required field, message = LOCS[:field_required], &blk
            modify_field field do |info|
                raise E2Error.new("Required condition already provided for field #{field} in model #{@model}") if blk && info[:required] && info[:required][:if]
                info[:required] = {message: message}
                info[:required][:if] = blk if blk
            end
        end

        def optional field
            modify_field field do |info|
                info.delete(:required)
                info[:optional] = true
            end
        end

        def optionals *fields
            fields.each{|f|optional f}
        end

        def dont_strip field
            modify_field field do |info|
                info[:dont_strip] = true
            end
        end

        def primary_key field
            modify_field field do |info|
                info[:primary_key] = true
            end
        end

        def fix_decimal field, size, scale
            modify_field field do |info|
                info[:validations][:decimal] = {
                    scale: scale,
                    size: size,
                    regexp: /^\d{,#{size - scale}}(?:\.\d{,#{scale}})?$/
                }
            end
        end

        # def validation field, name, opts = true
        #     modify_field field do |info|
        #         info[:validations][name] = opts
        #     end
        # end

        def unique field, *with
            depends_on(field, *with)
            modify_field field do |info|
                info[:transaction] = true
                info[:validations][:unique] = {with: with}
            end
        end

        def email field, message = LOCS[:invalid_email_format]
            modify_field field do |info|
                info[:type] = :email
            end
            format field, /\w+\@\w+\.\w+/, message
        end

        def password field
            modify_field field do |info|
                info[:type] = :password
            end
        end

        def file_store_field field, multiple = true, table = :files, store = {}
            # string_field field, 1000
            any_field field
            modify_field field do |info|
                info[:type] = :file_store
                info[:multiple] = multiple
                info[:table] = table
                info[:store] = store
                info[:store][:upload] ||= "#{Engine2::SETTINGS[:path]}/store/upload"
                info[:store][:files] ||= "#{Engine2::SETTINGS[:path]}/store/files"
                info[:transaction] = true
            end
        end

        def format field, pattern, message = LOCS[:invalid_format]
            modify_field field do |info|
                info[:validations][:format] = {pattern: pattern, message: message}
            end
        end

        def length field, len
            modify_field field do |info|
                info[:length] = len
            end
        end

        def date_range from, to
            depends_on(from, to)
            modify_field from do |info|
                # info[:type] = :date_range
                info[:other_date] = to
                info[:validations][:date_range] = true
            end
        end

        def date_time date, time
            depends_on(date, time)
            modify_field date do |info|
                info[:other_time] = time
                info[:validations][:date_time] = true
            end
        end

        def currency field, symbol = LOCS[:currency_symbol]
            modify_field field do |info|
                info[:type] = :currency
                info[:symbol] = symbol
                info[:validations][:currency] = true
            end
        end

        def blob_store_field name, name_field, mime_field
            optional name
            define_field :"#{name}_blob", :blob_store do |info|
                info[:bytes_field] = name
                info[:name_field] = name_field
                info[:mime_field] = mime_field
                info[:transaction] = true
            end
        end

        def foreign_blob_store_field assoc_name, name, name_field, mime_field
            assoc = @model.many_to_one_associations[assoc_name]
            raise E2Error.new("'many_to_one' association '#{assoc_name}' not found for model '#{@model}'") unless assoc
            define_field :"#{assoc[:key]}_blob", :foreign_blob_store do |info|
                info[:assoc_name] = assoc_name
                info[:bytes_field] = name
                info[:name_field] = name_field
                info[:mime_field] = mime_field
                info[:transaction] = true
            end
        end

        def many_to_one_field assoc_name
            assoc = @model.many_to_one_associations[assoc_name]
            raise E2Error.new("'many_to_one' association '#{assoc_name}' not found for model '#{@model}'") unless assoc
            keys = assoc[:keys]
            modify_field keys.first do |info|
                info[:type] = :many_to_one
                info[:keys] = keys
                info[:assoc_name] = assoc_name
            end
        end

        def star_to_many_field assoc_name, schemes = Schemes::STMF_LINK
            assoc = @model.one_to_many_associations[assoc_name] || @model.many_to_many_associations[assoc_name]
            raise E2Error.new("'*_to_many' association '#{assoc_name}' not found for model '#{@model}'") unless assoc
            define_field assoc_name, :string do |info|
                info[:type] = :star_to_many_field
                info[:schemes] = schemes
                info[:keys] = assoc[:keys]
                info[:assoc_name] = assoc_name
                info[:transaction] = true
            end
        end

        def list_select_bits values
            values.each_with_index.map{|a, i|[1 << i, a]}.to_h
        end

        def list_select name, options
            modify_field name do |info|
                info[:type] = :list_select
                values = options[:values]

                if options[:multiselect]
                    info[:multiselect] = true
                    case info[:otype]
                    when :string
                        info[:separator] = options[:separator] || ';'
                        info[:validations].delete(:string_length)
                    when :integer
                        info[:validations].delete(:integer)
                    end
                    info[:max_length] = options[:max_length] || 3
                    info[:max_length_html] = options[:max_length_html] || LOCS[:list_select_selected]
                end

                raise E2Error.new("type '#{values.class}' not supported for list_select modifier for field #{name}") unless values.is_a?(Hash)
                info[:values] = values.to_a
                info[:validations][:list_select] = true unless values.empty?
            end
        end

        def decode name, dinfo = {form: {scaffold: true}, search: {scaffold: true}}
            modify_field name do |info|
                raise E2Error.new("Field type of '#{name}' in model '#{@model}' needs to be 'many_to_one'") unless info[:type] == :many_to_one
                dec = info[:decode] ||= {}
                dec[:search].clear if dinfo[:search] && dec[:search]
                dec[:form].clear if dinfo[:form] && dec[:form]
                info[:decode].rmerge!(dinfo)
            end
        end

        def validate name, validation_name = nil, &blk
            raise E2Error.new("Local validation '#{validation_name}' in model '#{@model}' conflicts with builtin validation") if validation_name && Validations[validation_name]
            modify_field name do |info|
                info[:validations][validation_name || :"#{@model.table_name}_#{name}_#{info[:validations].size}"] = {lambda: blk}
            end
        end

        def sequence name, seq_name
            modify_field name do |info|
                info[:sequence] = seq_name
            end
        end
    end
end
