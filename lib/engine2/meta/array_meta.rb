# coding: utf-8

module Engine2
    class ArrayListMeta < Meta
        meta_type :list
        include MetaListSupport

        (DefaultFilters ||= {}).merge!(
            exact: lambda{|entries, name, value, type_info, hash|
                entries.select{|e|e[name] == value}
            },
            string: lambda{|entries, name, value, type_info, hash|
                entries.select{|e|e[name].to_s[value]}
            },
            boolean: lambda{|*args| DefaultFilters[:exact].(*args)},
            list_select: lambda{|*args| DefaultFilters[:exact].(*args)},
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

        def invoke handler
            params = handler.params
            # if params[:initial] || params[:refresh]
            entries = data_source(handler)

            per_page = lookup(:config, :per_page)
            page = params[:page].to_i
            handler.permit page >= 0 && page < 1000

            if order_str = params[:order]
                order = order_str.to_sym
                handler.permit lookup(:info, order, :sort)
                entries = entries.sort_by{|e|e[order].to_s}
                entries = entries.reverse if params[:asc] == "true"
            end

            if search = params[:search]
                entries = list_search(entries, handler, search)
            end

            {entries: entries.drop(page).take(per_page), count: entries.size}
        end

        def list_search entries, handler, search
            hash = JSON.parse(search, symbolize_names: true) rescue handler.halt_forbidden
            model = assets[:model]
            sfields = lookup(:search_fields)
            handler.permit sfields
            hash.each_pair do |name, value|
                handler.permit sfields.include?(name)

                type_info = get_type_info(name)
                entries = if filter = (@filters && @filters[name]) || (dynamic? && (static.filters && static.filters[name]))
                    filter.(entries, hash, handler)
                elsif filter = DefaultFilters[type_info[:type]]
                    filter.(entries, name, value, type_info, hash)
                else
                    raise E2Error.new("Filter not found for field '#{name}' in model '#{model}'") unless filter
                end

                handler.permit entries
            end

            entries
        end
    end
end