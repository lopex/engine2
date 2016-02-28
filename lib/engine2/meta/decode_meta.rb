# coding: utf-8

module Engine2
    class DecodeMeta < Meta
        include MetaQuerySupport

        def decode *fields, &blk
            query select(*fields), &blk
            @meta[:decode_fields] = fields
        end

        def separator sep
            @meta[:separator] = sep
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

        def post_run
            query select(*assets[:model].primary_keys) unless @query
            @meta[:separator] = '/' unless @meta[:separator]
            super
            @meta[:primary_fields] = assets[:model].primary_keys
        end
    end

    class DecodeListMeta < DecodeMeta
        meta_type :decode_list

        def invoke handler
            {entries: get_query.limit(200).all}
        end
    end

    class TypeAheadMeta < DecodeMeta
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
                condition = (@meta[:decode_fields] || @meta[:fields]).map{|f|f.like("%#{query}%")}.inject{|q, f| q | f}
                {entries: get_query.where(condition).limit(@meta[:limit]).all}
            else
                handler.permit id = handler.params[:id]
                record = get_query[Hash[assets[:model].primary_keys.zip(split_keys(id))]]
                # handler.halt_not_found(LOCS[:no_entry]) unless record
                {entry: record}
            end
        end
    end

    class DecodeEntryMeta < DecodeMeta
        meta_type :decode_entry

        def invoke handler
            {entries: invoke_decode(handler, handler.param_to_json(:ids))}
        end

        def invoke_decode handler, ids
            records = get_query.where(ids.map{|keys| Hash[assets[:model].primary_keys.zip(keys)]}.inject{|q, c| q | c}).all
            # handler.halt_not_found(LOCS[:no_entry]) if records.empty?
            records
        end

        def post_run
            super
            if assets[:assoc]
                keys = assets[:assoc][:keys]
                parent_meta = action.parent.parent.*
                key = parent_meta.get[:info][keys.first]
                # render = key[:render]
                if key
                    render = key[:render]
                    if render && render[:multiple]
                        action.list.*.menu(:panel_menu).option_at 0, :choose, icon: :ok # , disabled: "action.selected_size() == 0"
                    end
                end
            end
        end
    end
end