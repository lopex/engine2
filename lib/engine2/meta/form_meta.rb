# coding: utf-8

module Engine2
    class FormMeta < Meta
        include MetaFormSupport, MetaQuerySupport
    end

    class CreateMeta < FormMeta
        meta_type :create

        def pre_run
            super
            panel_title LOCS[:create_title]
            action.parent.*.menu(:menu).option_at 0, action.name, icon: "plus-sign", button_loc: false

            hide_pk unless assets[:model].natural_key
        end

        def record handler, record
            create_record(handler, record)
        end

        def create_record handler, record
        end

        def invoke handler
            record = {}
            if assoc = assets[:assoc]
                case assoc[:type]
                when :one_to_many
                    handler.permit parent = handler.params[:parent_id]
                    assoc[:keys].zip(split_keys(parent)).each{|key, val| record[key] = val}
                end
            end
            static.record(handler, record)
            {record: record, new: true}
        end
    end

    class ModifyMeta < FormMeta
        meta_type :modify

        def pre_run
            super
            panel_title LOCS[:modify_title]
            action.parent.*.menu(:item_menu).option action.name, icon: "pencil", button_loc: false
        end

        def record handler, record
            modify_record(handler, record)
        end

        def modify_record handler, record
        end

        def invoke handler
            handler.permit id = handler.params[:id]
            record = get_query[assets[:model].primary_keys_hash_qualified(split_keys(id))]

            if record
                static.record(handler, record)
                {record: record}
            else
                handler.halt_not_found LOCS[:no_entry]
            end
        end

        def post_run
            super
            assets[:model].primary_keys.each do |key| # pre_run ?
                info! key, disabled: true
            end
        end
    end

end
