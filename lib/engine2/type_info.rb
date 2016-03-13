# coding: utf-8

module Engine2

    class TypeInfo
        def initialize model
            @model = model
            @info = model.type_info
        end

        def define_field field, type # , opts = {}
            info = @info[field]
            raise E2Error.new("Field '#{field}' already defined in model '#{@model}'") if info && info[:type]

            unless info
                @info[field] = info = {dummy: true}
                @model.dummies << field
            end

            info.merge!({
                name: field,
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

        def date_field field, format, model_format
            define_field field, :date do |info|
                info[:format] = format
                info[:model_format] = model_format
                info[:validations][:date] = true
            end
        end

        def time_field field, format, model_format
            define_field field, :time do |info|
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
                # info[]
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

        def primary field
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

        def file_store_field field, multiple = true, table = :files
            # string_field field, 1000
            any_field field
            modify_field field do |info|
                info[:type] = :file_store
                info[:table] = table
                info[:multiple] = multiple
                info[:transaction] = true
            end
        end

        def format field, pattern, message = LOCS[:invalid_format]
            modify_field field do |info|
                info[:validations][:format] = {pattern: pattern, message: message}
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

        def boolean field, true_value = 1, false_value = 0
            modify_field field do |info|
                info[:type] = :boolean
                info[:true_value] = true_value
                info[:false_value] = false_value
                info[:validations][:boolean] = true
            end
        end

        def currency field
            modify_field field do |info|
                info[:type] = :currency
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
            assoc = @model.association_reflections[assoc_name]
            raise E2Error.new("Associaction '#{assoc_name}' not found for model '#{@model}'") unless assoc
            raise E2Error.new("Association '#{assoc_name}' in model '#{@mode}' is not of type many_to_one") unless assoc[:type] == :many_to_one
            define_field :"#{assoc[:key]}_blob", :foreign_blob_store do |info|
                info[:assoc_name] = assoc_name
                info[:bytes_field] = name
                info[:name_field] = name_field
                info[:mime_field] = mime_field
                info[:transaction] = true
            end
        end

        def many_to_one_field assoc_name  # field, keys,
            assoc = @model.association_reflections[assoc_name]
            raise E2Error.new("Associaction '#{assoc_name}' not found for model '#{@model}'") unless assoc
            raise E2Error.new("Association '#{assoc_name}' in model '#{@mode}' is not of type many_to_one") unless assoc[:type] == :many_to_one
            keys = assoc[:keys]
            modify_field keys.first do |info|
                info[:type] = :many_to_one
                info[:keys] = keys
                info[:assoc_name] = assoc_name
            end
        end

        def star_to_many_field assoc_name # , keys, assoc_name
            assoc = @model.association_reflections[assoc_name]
            raise E2Error.new("Associaction '#{assoc_name}' not found for model '#{@model}'") unless assoc
            raise E2Error.new("Association '#{assoc_name}' in model '#{@model}' is not of type *_to_many") unless [:one_to_many, :many_to_many].include?(assoc[:type])
            define_field assoc_name, :string do |info|
                info[:type] = :star_to_many
                info[:keys] = assoc[:keys]
                info[:assoc_name] = assoc_name
                info[:transaction] = true # ?
            end
        end

        def list_select name, list
            modify_field name do |info|
                info[:type] = :list_select
                info[:list] = case list
                    when Hash
                        # list.map{|k, v| {id: k, value: v}}
                        list.to_a
                    else
                        raise E2Error.new("type not supported for list_select modifier for field #{name}")
                end
                info[:validations][:list_select] = true
            end
        end

        def decode name, dinfo = {form: {scaffold: true}, search: {scaffold: true}}
            modify_field name do |info|
                raise E2Error.new("Field type of #{name} needs to be :many_to_one") unless info[:type] == :many_to_one
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

        def filter name, &blk
            modify_field name do |info|
                info[:filter] = blk
            end
        end

        def order name, &blk
            modify_field name do |info|
                info[:order] = blk
            end
        end

    end
end