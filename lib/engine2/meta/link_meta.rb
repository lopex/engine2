# coding: utf-8

module Engine2
    class StarToManyLinkMeta < Meta
        include MetaModelSupport
        http_method :post
        meta_type :star_to_many_link

        def invoke handler
            json = handler.post_to_json
            parent = json[:parent_id]
            ids = json[:ids]
            handler.permit parent && ids
            model = assets[:model]
            assoc = assets[:assoc]
            case assoc[:type]
            when :one_to_many
                model.db.transaction do
                    self.class.one_to_many_link_db model, assoc, split_keys(parent), ids
                end
                {}
            when :many_to_many
                self.class.many_to_many_link_db model, assoc, split_keys(parent), ids
                {}
            else unsupported_association
            end
        end

        def self.one_to_many_link_db model, assoc, parent, ids
            pk = Hash[assoc[:keys].zip(parent)]
            ids.each do |id|
                model.where(model.primary_keys_hash(Sequel::split_keys(id))).update(pk)
            end
        end

        def self.many_to_many_link_db model, assoc, parent, ids
            p_pk = Hash[assoc[:left_keys].zip(parent)]
            values = ids.map do |id|
                p_pk.merge Hash[assoc[:right_keys].zip(Sequel::split_keys(id))]
            end
            model.db[assoc[:join_table]].multi_insert values
        end
    end

    class StarToManyUnlinkMetaBase < Meta
        include MetaModelSupport
        http_method :delete

        def one_to_many_unlink_db handler, ids
            model = assets[:model]
            assoc = assets[:assoc]
            keys = assoc[:keys]
            if keys.all?{|k|model.db_schema[k][:allow_null] == true}
                model.db.transaction do
                    self.class.one_to_many_unlink_db model, assoc, ids
                end
                {}
            else
                handler.halt_method_not_allowed LOCS[:"non_nullable"]
            end
        end

        def self.one_to_many_unlink_db model, assoc, ids
            keys = assoc[:keys]
            ids.each do |id|
                model.where(model.primary_keys_hash(Sequel::split_keys(id))).update(Hash[keys.zip([nil])])
            end
        end

        def many_to_many_unlink_db parent, ids
            model = assets[:model]
            assoc = assets[:assoc]

            model.db.transaction do
                self.class.many_to_many_unlink_db model, assoc, Sequel::split_keys(parent), ids
            end
            {}
        end

        def self.many_to_many_unlink_db model, assoc, parent, ids
            p_pk = Hash[assoc[:left_keys].zip(parent)]
            ds = model.db[assoc[:join_table]]
            ids.each do |id|
                ds.where(p_pk, Hash[assoc[:right_keys].zip(Sequel::split_keys(id))]).delete
            end
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
            assoc = assets[:assoc]
            case assoc[:type]
            when :one_to_many
                one_to_many_unlink_db(handler, [id])
            when :many_to_many
                handler.permit parent = handler.params[:parent_id]
                many_to_many_unlink_db(parent, [id])
            else unsupported_association
            end
        end
    end

    class StarToManyBulkUnlinkMeta < StarToManyUnlinkMetaBase
        meta_type :star_to_many_bulk_unlink

        def pre_run
            super
            action.parent.parent.*.menu(:menu).option_after :default_order, :confirm_bulk_unlink, icon: "minus", show: "action.selected_size() > 0", button_loc: false
        end

        def invoke handler
            ids = handler.param_to_json(:ids)
            handler.permit ids.is_a?(Array)
            assoc = assets[:assoc]
            case assoc[:type]
            when :one_to_many
                one_to_many_unlink_db(handler, ids)
            when :many_to_many
                handler.permit parent = handler.params[:parent_id]
                many_to_many_unlink_db(parent, ids)
            else unsupported_association
            end
        end
    end
end
