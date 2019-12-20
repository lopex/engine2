# coding: utf-8
# frozen_string_literal: true

module Engine2
    class ArrayListAction < Action
        action_type :list
        include ActionListSupport

        (DefaultFilters ||= {}).merge!(
            exact: lambda{|entries, name, value, type_info, hash|
                entries.select{|e|e[name] == value}
            },
            string: lambda{|entries, name, value, type_info, hash|
                if type_info[:type] == :list_select
                    if type_info[:multiselect]
                        entries.select{|e|value.include?(e[name].to_s)}
                    else
                        entries.select{|e|e[name].to_s == value}
                    end
                else
                    entries.select{|e|e[name].to_s[value]}
                end

            },
            boolean: lambda{|*args| DefaultFilters[:exact].(*args)},
            integer: lambda{|entries, name, value, type_info, hash|
                if value.is_a? Hash
                    from, to = value[:from], value[:to]
                    if from && to
                        entries.select{|e|e[name] >= from.to_i && e[name] <= to.to_i}
                    else
                        entries.select{|e| from ? e[name] >= from.to_i : e[name] <= to.to_i}
                    end
                elsif value.is_a? Integer
                    entries.select{|e|e[name] == value.to_i}
                else
                    nil
                end
            }
        )

        def data_source handler
            []
        end

        def page_frame handler, entries
            entries
        end

        def invoke handler
            params = handler.params
            # if params[:initial] || params[:refresh]
            entries = data_source(handler)

            per_page = lookup(:config, :per_page)
            page = params[:page].to_i
            handler.permit page >= 0 && page < 1000

            if order_str = params[:order]
                order = order_str.to_sym
                handler.permit lookup(:fields, order, :sort)
                entries = entries.sort_by{|e|e[order].to_s}
                entries = entries.reverse if params[:asc] == "true"
            end

            if search = params[:search]
                entries = list_search(entries, handler, search)
            end

            {entries: page_frame(handler, entries[page, per_page]), count: entries.size}
        end

        def list_search entries, handler, search
            hash = JSON.parse(search, symbolize_names: true) rescue handler.halt_forbidden
            model = assets[:model]
            sfields = lookup(:search_field_list)
            handler.permit sfields
            hash.each_pair do |name, value|
                handler.permit sfields.include?(name)

                type_info = model.find_type_info(name)
                entries = if filter = (@filters && @filters[name]) || (dynamic? && (static.filters && static.filters[name]))
                    filter.(handler, entries, hash)
                elsif filter = DefaultFilters[type_info[:otype]]
                    filter.(entries, name, value, type_info, hash)
                else
                    raise E2Error.new("Filter not found for field '#{name}' in model '#{model}'") unless filter
                end

                handler.permit entries
            end

            entries
        end
    end

    class ArrayViewAction < Action
        include ActionViewSupport

        def find_record handler, id
            node.parent.*.data_source(handler)[id.to_i]
        end
    end

    class ArrayFormAction < Action
    end

    class ArrayCreateAction < ArrayFormAction
        include ActionCreateSupport
    end

    class ArrayModifyAction < ArrayFormAction
        include ActionModifySupport

        def find_record handler, id
            node.parent.*.data_source(handler)[id.to_i]
        end
    end

    class ArrayDeleteAction < Action
        include ActionDeleteSupport

        def invoke handler
            handler.permit id = handler.params[:id]
            node.parent.parent.*.data_source(handler).delete_at(id.to_i)
        end
    end

    class ArraySaveAction < Action
        include ActionApproveSupport
    end

    class ArrayInsertAction < ArraySaveAction
        include ActionInsertSupport
        action_type :approve

        def after_approve handler, record
            # handler.permit id = record[:id]
            # ds = node.parent.parent.*.data_source(handler)
        end
    end

    class ArrayUpdateAction < ArraySaveAction
        include ActionUpdateSupport
        action_type :approve

        def after_approve handler, record
            handler.permit id = record[:id]
            node.parent.parent.*.data_source(handler)[id].merge!(record.values)
        end
    end

    class Schemes
        ARRAY_CRUD ||= {array_create: true, array_view: true, array_modify: true, array_delete: true}.freeze
        ARRAY_VIEW ||= {array_view: true}
    end

    SCHEMES.instance_eval do
        define_scheme :array_view do |name = :view|
            define_node name, ArrayViewAction
        end

        define_scheme :array_modify do |name = :modify|
            define_node name, ArrayModifyAction do
                define_node :approve, ArrayUpdateAction
            end
        end

        define_scheme :array_create do |name = :create|
            define_node name, ArrayCreateAction do
                define_node :approve, ArrayInsertAction
            end
        end

        define_scheme :array_delete do
            run_scheme :confirm, :delete, ArrayDeleteAction,
                message: LOCS[:delete_question], title: LOCS[:confirm_delete_title]
        end

        define_scheme :array do |name, model, options|
            options ||= Schemes::ARRAY_CRUD
            define_node name, ArrayListAction, model: model do
                options.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :create, :modify if options[:array_create] && options[:array_modify]
            end
        end
    end
end
