# coding: utf-8

module Engine2
    class StarToManyLinkMeta < Meta
        include MetaModelSupport
        http_method :post
        meta_type :star_to_many_link

        def pre_run
            super
            execute 'action.errors || [action.parent().invoke(), action.panel_close()]'
        end

        def invoke handler
            json = handler.post_to_json
            parent = json[:parent_id]
            ids = json[:ids]
            handler.permit parent && ids
            invoke_link_db handler, split_keys(parent), ids
        end

        def invoke_link_db handler, parent, ids
            model = assets[:model]
            assoc = assets[:assoc]

            case assoc[:type]
            when :one_to_many
                model.db.transaction do
                    pk = Hash[assoc[:keys].zip(parent)]
                    ids.each do |id|
                        model.where(model.primary_keys_hash(split_keys(id))).update(pk)
                    end
                end
            when :many_to_many
                p_pk = Hash[assoc[:left_keys].zip(parent)]
                values = ids.map do |id|
                    p_pk.merge Hash[assoc[:right_keys].zip(split_keys(id))]
                end
                model.db[assoc[:join_table]].multi_insert values
            else unsupported_association
            end
            {}
        end
    end

    class StarToManyUnlinkMetaBase < Meta
        include MetaModelSupport
        http_method :delete

        def pre_run
            super
            execute '[action.parent().invoke(), action.panel_close()]'
        end

        def invoke_unlink_db handler, parent, ids
            model = assets[:model]
            assoc = assets[:assoc]

            case assoc[:type]
            when :one_to_many
                keys = assoc[:keys]
                if keys.all?{|k|model.db_schema[k][:allow_null] == true}
                    model.db.transaction do
                        ids.each do |id|
                            model.where(model.primary_keys_hash(split_keys(id))).update(Hash[keys.zip([nil])])
                        end
                    end
                else
                    handler.halt_method_not_allowed LOCS[:"non_nullable"]
                end
            when :many_to_many
                model.db.transaction do
                    p_pk = Hash[assoc[:left_keys].zip(parent)]
                    ds = model.db[assoc[:join_table]]
                    ids.each do |id|
                        ds.where(p_pk, Hash[assoc[:right_keys].zip(split_keys(id))]).delete
                    end
                end
            else unsupported_association
            end
            {}
        end
    end

    class StarToManyUnlinkMeta < StarToManyUnlinkMetaBase
        meta_type :star_to_many_unlink

        def pre_run
            super
            action.parent.parent.*.menu(:item_menu).option :confirm_unlink, icon: "minus", show: "action.selected_size() == 0", button_loc: false
        end

        def invoke handler
            handler.permit id = handler.params[:id]
            handler.permit parent = handler.params[:parent_id]
            invoke_unlink_db handler, split_keys(parent), [id]
        end
    end

    class StarToManyBulkUnlinkMeta < StarToManyUnlinkMetaBase
        meta_type :star_to_many_bulk_unlink

        def pre_run
            super
            action.parent.parent.*.select_toggle_menu
            action.parent.parent.*.menu(:menu).option_after :default_order, :confirm_bulk_unlink, icon: "minus", show: "action.selected_size() > 0", button_loc: false
        end

        def invoke handler
            ids = handler.param_to_json(:ids)
            handler.permit parent = handler.params[:parent_id]
            handler.permit ids.is_a?(Array)
            invoke_unlink_db handler, split_keys(parent), ids
        end
    end
end
