# coding: utf-8

module Engine2
    class DecodeAction < Action
        include ActionAPISupport, ActionModelSupport, ActionQuerySupport

        def decode *fields, &blk
            query select(*fields), &blk
            @meta[:decode_fields] = fields
        end

        def separator sep
            @meta[:separator] = sep
        end

        def show_max_selected max
            @meta[:show_max_selected] = max
        end

        def post_process
            if fields = @meta[:fields]
                fields = fields - static.get[:fields] if dynamic?
                # no decorate here
                fields.each do |name|
                    type_info = assets[:model].type_info[name] # foreign keys ?
                    proc = ListRendererPostProcessors[type_info[:type]] # like... checkboxes, list_selects
                    proc.(self, name, type_info) if proc
                end
            end
            # no super
        end

        def pre_run
            super
            if assoc = assets[:assoc]
                decode = assoc[:model].type_info[assoc[:keys].first][:decode]
                if decode[:search][:multiple]
                    show_max_selected 3
                    loc! decode_selected: LOCS[:decode_selected]
                end
            end
        end

        def post_run
            decode(*assets[:model].primary_keys) unless @query
            @meta[:separator] = '/' unless @meta[:separator]
            super
            @meta[:primary_fields] = assets[:model].primary_keys
        end

    end

    class DecodeListAction < DecodeAction
        meta_type :decode_list

        def invoke handler
            {entries: get_query.limit(200).all}
        end
    end

    class TypeAheadAction < DecodeAction
        meta_type :typeahead

        def pre_run
            super
            limit 10
        end

        def limit lmt
            @meta[:limit] = lmt
        end

        def invoke handler
            if query = handler.params[:query]
                condition = @meta[:decode_fields].map{|f|f.like("%#{query}%")}.reduce{|q, f| q | f}
                {entries: get_query.where(condition).limit(@meta[:limit]).all}
            else
                handler.permit id = handler.params[:id]
                record = get_query[Hash[assets[:model].primary_keys.zip(split_keys(id))]]
                # handler.halt_not_found(LOCS[:no_entry]) unless record
                {entry: record}
            end
        end
    end

    class DecodeEntryAction < DecodeAction
        meta_type :decode_entry

        def invoke handler
            {entries: invoke_decode(handler, handler.param_to_json(:ids))}
        end

        def invoke_decode handler, ids
            records = get_query.where(ids.map{|keys| Hash[assets[:model].primary_keys.zip(keys)]}.reduce{|q, c| q | c}).all
            # handler.halt_not_found(LOCS[:no_entry]) if records.empty?
            records
        end

        def post_run
            super
            if assoc = assets[:assoc]
                decode = assoc[:model].type_info[assoc[:keys].first][:decode]

                if decode[:search][:multiple] && node.parent.parent.*.is_a?(ListAction)
                    node.list.*.menu(:panel_menu).option :choose, icon: :ok #, disabled: "action.selected_size() == 0"
                    node.list.*.menu(:panel_menu).option :cancel, icon: "remove"
                end
            end
        end
    end
end