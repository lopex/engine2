# coding: utf-8

module Engine2
    class ListMeta < Meta
        meta_type :list
        include MetaListSupport, MetaQuerySupport

        def post_run
            query select(*assets[:model].columns.reject{|col| assets[:model].type_info[col][:length].to_i > 20}.take(10)) unless @query
            super
            @meta[:primary_fields] = assets[:model].primary_keys
        end

        def invoke handler
            params = handler.params
            model = assets[:model]
            query = list_context(get_query, handler)

            if search = params[:search]
                query = list_search(query, handler, search)
            end

            count = query.count if lookup(:config, :use_count)

            if order_str = params[:order]
                order = order_str.to_sym
                handler.permit lookup(:info, order, :sort)

                type_info = model.type_info[order]
                if type_info && order_blk = type_info[:order]
                    query = order_blk.(query)
                else
                    # order = order.qualify(model.table_name) unless order_str.include?('__')
                    order = order.qualify(model.table_name) if type_info
                    query = query.order(order)
                end

                query = query.reverse if params[:asc] == "true"
            end

            per_page = lookup(:config, :per_page)
            page = params[:page].to_i
            handler.permit page >= 0 && page < 1000

            query = query.limit(per_page, page)

            res = {entries: query.all}
            res[:count] = count if count
            res
        end

        def list_search query, handler, search
            hash = JSON.parse(search, symbolize_names: true) rescue handler.halt_forbidden
            model = assets[:model]
            sfields = lookup(:search_fields)
            handler.permit sfields
            hash.each_pair do |name, value|
                handler.permit sfields.include?(name)

                type_info = get_type_info(name)
                filter = type_info[:filter] || DefaultFilters[type_info[:otype]]
                # handler.permit filter
                raise E2Error.new("Filter not found for field #{name} in model #{model}") unless filter
                name = model.type_info[name] ? name.qualify(model.table_name) : Sequel.expr(name)
                query = filter.(query, name, value, type_info, hash)
                handler.permit query
            end
            query
        end

        def list_context query, handler
            query
        end
    end

    #
    # Many to One
    #
    class ManyToOneListMeta < ListMeta
        meta_type :many_to_one_list
    end

    #
    # * to Many
    #
    class StarToManyListMeta < ListMeta
        meta_type :star_to_many_list
        def pre_run
            super
            panel_title "#{glyphicon('list')} #{LOCS[assets[:assoc][:name]]}"
        end

        # def decode_panel_title handler
        #     if handler.initial?
        #         # Hash[assets[:model].primary_keys.zip(split_keys(id))]]
        #         p action.parent.decode_entry.*.invoke_decode([[handler.params[:parent_id]]])
        #         panel_title "ADFASDF"
        #     end
        # end

        # def post_run
        #     super
        #     unless @request_meta_proc
        #         request{|h| decode_panel_title h}
        #     end
        # end

        def list_context query, handler
            handler.permit parent = handler.params[:parent_id]
            model = assets[:model]
            assoc = assets[:assoc]
            case assoc[:type]
            when :one_to_many
                keys = assoc[:keys]
                hash = Hash[keys.map{|k| k.qualify(model.table_name)}.zip(split_keys(parent))]
                if handler.params[:negate]
                    query = query.exclude(hash)
                    query = query.or(Hash[keys.zip([nil])]) if keys.all?{|k|model.db_schema[k][:allow_null] == true} # type_info[:required] ?
                    query
                else
                    query.where(hash)
                end
            when :many_to_many
                q_pk = model.primary_keys_qualified
                j_table = assoc[:join_table]
                l_keys = assoc[:left_keys].map{|k| k.qualify(j_table)}
                r_keys = assoc[:right_keys].map{|k| k.qualify(j_table)}
                r_keys_vals = Hash[r_keys.zip(q_pk)]
                l_keys_vals = Hash[l_keys.zip(split_keys(parent))]

                if handler.params[:negate]
                    query.exclude(model.db[j_table].select(nil).where(r_keys_vals, l_keys_vals).exists)
                else
                    # query.qualify.join(j_table, [r_keys_vals, l_keys_vals])
                    query.qualify.left_join(j_table, r_keys_vals).filter(l_keys_vals)
                end
            else unsupported_association
            end
        end
    end

    class StarToManyLinkListMeta < StarToManyListMeta
        meta_type :star_to_many_link_list
        def pre_run
            super
            config.merge!(selectable: false)
            panel_title LOCS[:link_title]
            menu(:panel_menu).option_at 0, :link, icon: "ok", enabled: "action.selected_size() > 0"
            action.parent.*.menu(:menu).option_at 0, :link_list, icon: "paperclip", button_loc: false
        end
    end

    # *_to_many_field
    class StarToManyFieldMeta < StarToManyListMeta
        meta_type :star_to_many_field

        def pre_run
            super
            modal_action false
            panel_panel_template false
            # panel_template nil
        end

        def list_context query, handler
            unlinked = handler.param_to_json(:unlinked)
            linked = handler.param_to_json(:linked)
            query = super(query, handler)
            model = assets[:model]
            pks = model.primary_keys_qualified

            if handler.params[:negate]
                query = unlinked.map{|ln| pks.zip(split_keys(ln))}.inject(query){|q, c| q.or c}
                # query = query.or *unlinked.map{|unl| Hash[model.primary_keys.zip(split_keys(unl))]}.inject{|q, c| q | c}
                query = query.where *linked.map{|ln| pks.zip(split_keys(ln)).sql_negate}

            else
                query = query.where *unlinked.map{|unl| pks.zip(split_keys(unl)).sql_negate}
                # query = query.or *linked.map{|ln| model.primary_keys.zip(split_keys(ln))}
                # query = query.or *linked.map{|ln| Hash[model.primary_keys.zip(split_keys(ln))]}.inject{|q, c| q | c}
                case assets[:assoc][:type]
                when :one_to_many
                    query = linked.map{|ln| pks.zip(split_keys(ln))}.inject(query){|q, c| q.or c}
                when :many_to_many
                    query = linked.map{|ln| pks.zip(split_keys(ln))}.inject(query){|q, c| q.or c}.distinct
                else unsupported_association
                end unless linked.empty?
            end

            query
        end
    end

    class StarToManyFieldUnlinkMeta < Meta
        meta_type :star_to_many_field_unlink

        def pre_run
            super
            action.parent.parent.*.menu(:item_menu).option :confirm_unlink, icon: "minus", show: "action.selected_size() == 0", button_loc: false
        end
    end

    class StarToManyFieldLinkListMeta < StarToManyFieldMeta
        meta_type :star_to_many_field_link_list

        def pre_run
            super
            config.merge!(selectable: false)
            modal_action true
            panel_panel_template 'scaffold/list'
            panel_title LOCS[:link_title]
            menu(:panel_menu).option_at 0, :link, icon: "ok", enabled: "action.selected_size() > 0"
            action.parent.*.menu(:menu).option_at 0, :link_list, icon: "paperclip", button_loc: false
        end
    end
end

