# coding: utf-8
# frozen_string_literal: true

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
            if fields = @meta[:field_list]
                fields = fields - static.meta[:field_list] if dynamic?
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
        action_type :decode_list

        def invoke handler
            {entries: get_query.limit(200).load_all}
        end

        def order *fields
            @query = get_query.order *fields
        end
    end

    class TypeAheadAction < DecodeAction
        action_type :typeahead

        def pre_run
            super
            @limit = 10
        end

        def limit lmt
            @limit = lmt
        end

        def get_limit
            @limit
        end

        def get_case_insensitive
            @case_insensitive
        end

        def case_insensitive
            @case_insensitive = true
        end

        def order *fields
            @query = get_query.order *fields
        end

        def invoke handler
            model = assets[:model]
            if query = handler.params[:query]
                fields = @meta[:decode_fields] || static.meta[:decode_fields]

                entries = if query.to_s.empty?
                    get_query
                else
                    condition = fields.map{|f|f.like("%#{query}%", case_insensitive: @case_insensitive || static.get_case_insensitive)}.reduce{|q, f| q | f}
                    get_query.where(condition)
                end.limit(@limit || static.get_limit).load_all

                {entries: entries}
            else
                handler.permit id = handler.params[:id]
                record = get_query.load Hash[model.primary_keys_qualified.zip(split_keys(id))]
                # handler.halt_not_found(LOCS[:no_entry]) unless record
                {entry: record}
            end
        end
    end

    class DecodeEntryAction < DecodeAction
        action_type :decode_entry

        def invoke handler
            {entries: invoke_decode(handler, handler.param_to_json(:ids))}
        end

        def invoke_decode handler, ids
            records = get_query.where(ids.map{|keys| Hash[assets[:model].primary_keys.zip(keys)]}.reduce{|q, c| q | c}).load_all
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