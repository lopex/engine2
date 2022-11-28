# coding: utf-8
# frozen_string_literal: true

module Engine2
    class ListAction < Action
        action_type :list
        include ActionListSupport, ActionQuerySupport

        (DefaultFilters ||= {}).merge!(
            string: lambda{|query, name, value, type_info, hash|
                name = type_info[:qualified_json_op].get_text(['{}']) if type_info[:qualified_json_op]
                case type_info[:type]
                when :list_select
                    raise E2Error.new("Filter unimplemented for string multi list_select, field: '#{name.to_sym}'") if type_info[:multiselect] # todo
                    query.where(name => value)
                when :many_to_one
                    query.where(name => value)
                when :many_to_many
                    table = query.model.many_to_many_associations[type_info[:assoc_name]].associated_class.table_name
                    query.association_join(:group).where(table.q(type_info[:column]).like("%#{value}%")).group(query.model.primary_keys_qualified)
                else
                    query.where(name.like("%#{value}%"))
                end
            },
            date: lambda{|query, name, value, type_info, hash|
                if value.is_a? Hash
                    from, to = value[:from], value[:to]
                    if from && to
                        query.where(name => from .. to)
                    elsif from
                        query.where(name >= Sequel.string_to_date(from))
                    elsif to
                        query.where(name <= Sequel.string_to_date(to))
                    else
                        query # ?
                    end
                else
                    query.where(name => Sequel.string_to_date(value))
                end
            },
            datetime: lambda{|query, name, value, type_info, hash|
                if value.is_a? Hash
                    DefaultFilters[:date].(query, name, value, type_info, hash)
                else
                    query.where(:date.sql_function(name) => Sequel.string_to_date(value))
                end
            },
            integer: lambda{|query, name, value, type_info, hash|
                if value.is_a? Hash
                    from, to = value[:from], value[:to]
                    if from && to
                        query.where(name => from .. to)
                    else
                        query.where(from ? name >= from.to_i : name <= to.to_i)
                    end
                elsif value.is_a?(Integer) || value.is_a?(String)
                    query.where(name => value.to_i)
                elsif value.is_a? Array
                    if !value.empty?
                        case type_info[:type]
                        when :many_to_one
                            keys = type_info[:keys]
                            if keys.length == 1
                                query.where(name => value)
                            else
                                query.where(keys.map{|k| hash[k]}.transpose.map{|vals| Hash[keys.zip(vals)]}.reduce{|q, c| q | c})
                            end
                        when :list_select
                            if type_info[:multiselect]
                                query.where(~{(name.sql_number & value.reduce(0, :|)) => 0})
                            else
                                query.where(name => value) # decode in sql query ?
                            end
                        when :integer
                            query = query.where(name => value)
                            query.opts[:join].any?{|j|j.table == type_info[:owner].table_name} ? query.group(query.model.primary_keys_qualified) : query
                        else
                            nil
                        end
                    else
                        nil
                    end
                else
                    nil
                end
            },
            boolean: lambda{|query, name, value, type_info, hash|
                query.where(name => value)
            }
        )

        def post_run
            query select(*assets[:model].columns.reject{|col| assets[:model].type_info[col][:length].to_i > 20}.take(10)) unless @query
            super
        end

        def page_frame handler, entries
            entries
        end

        def invoke handler
            params = handler.params
            model = assets[:model]
            query = list_context(get_query, handler)

            if search = params[:search]
                query = list_search(query, handler, search)
            elsif @filters || static.filters
                static.filters.to_h.merge(@filters.to_h).each do |name, filter|
                    query = filter.(handler, query, {})
                    handler.permit query
                end
            end

            count = query.count if lookup(:config, :use_count)

            if order = params[:order]
                order = order.to_sym
                handler.permit lookup(:fields, order, :sort)
                query = list_order(query, handler, order, params[:asc] == "true")
            elsif order = @default_order_field || static.default_order_field
                query = list_order(query, handler, order, true)
            end

            per_page = lookup(:config, :per_page)
            page = params[:page].to_i
            handler.permit page >= 0 && page < 1000000

            query = query.limit(per_page, page)

            entries = page_frame(handler, query.load_all)
            IdEncoder::instance.encode_list(entries, model)
            res = {entries: entries}
            res[:count] = count if count
            res
        end

        def list_search query, handler, search
            hash = JSON.parse(search, symbolize_names: true) rescue handler.halt_forbidden
            model = assets[:model]
            IdEncoder::instance.decode_associations(hash, model)

            sfields = lookup(:search_field_list)
            handler.permit sfields

            filters = @filters || static.filters ? static.filters.to_h.merge(@filters.to_h) : {}

            sfields.each do |name|
                info = model.find_type_info(name)
                name_sym = name.to_sym

                filter = filters[name_sym]
                if !(value = hash[name_sym]).nil? # use key?
                    query = if filter
                        filter.(handler, query, hash)
                    elsif filter = DefaultFilters[info[:otype]]
                        if name.is_a?(Symbol)
                            name = model.table_name.q(name)
                        else
                            joins = query.opts[:join]
                            query = query.association_join(name.table) unless (joins && joins.any?{|j|j.table == name.table})
                        end

                        filter.(query, name, value, info, hash)
                    else
                        raise E2Error.new("Filter not found for field '#{name}' in model '#{model}'") unless filter
                    end
                    handler.permit query
                else
                    if filter
                        query = filter.(handler, query, hash)
                        handler.permit query
                    end
                end
            end

            # hash.each_pair do |name, value|
            #     handler.permit name = sfields.find{|sf|sf.to_sym == name}
            #     type_info = model.find_type_info(name)
            #     query = if filter = (@filters && @filters[name]) || (dynamic? && (static.filters && static.filters[name]))
            #         filter.(handler, query, hash)
            #     elsif filter = DefaultFilters[type_info[:otype]]
            #         name = model.type_info[name] ? model.table_name.q(name) : Sequel.expr(name)
            #         filter.(query, name, value, type_info, hash)
            #     else
            #         raise E2Error.new("Filter not found for field '#{name}' in model '#{model}'") unless filter
            #     end
            #     handler.permit query
            # end

            query
        end

        def list_order query, handler, order, asc
            model = assets[:model]
            query = if order_blk = (@orders && @orders[order]) || (dynamic? && (static.orders && static.orders[order]))
                order_blk.(handler, query)
            else
                if info = model.type_info[order]
                    order = info[:qualified_json_op] || model.table_name.q(order)
                end
                query.order(order)
            end

            asc ? query : query.reverse
        end

        def list_context query, handler
            query
        end
    end

    #
    # Many to One
    #
    class ManyToOneListAction < ListAction
        action_type :many_to_one_list

        def pre_run
            super
        end
    end

    #
    # * to Many
    #
    class StarToManyListAction < ListAction
        action_type :star_to_many_list
        def pre_run
            super
            menu(:panel_menu).option_at 0, :close, icon: "remove"
            panel_title "#{assets[:model].model_icon.icon} #{LOCS[assets[:assoc][:name]]}"
        end

        def list_context query, handler
            handler.permit parent = handler.params[:parent_id]
            model = assets[:model]
            assoc = assets[:assoc]
            parent_keys = split_keys(parent)
            case assoc[:type]
            when :one_to_many
                keys = assoc[:keys]
                condition = parent_keys.all?{|k|k.to_s.empty?} ? false : Hash[keys.map{|k| model.table_name.q(k)}.zip(parent_keys)]
                if handler.params[:negate]
                    query = query.exclude(condition)
                    query = query.or(Hash[keys.zip([nil])]) if keys.all?{|k|model.db_schema[k][:allow_null] == true} # type_info[:required] ?
                    query
                else
                    query.where(condition)
                end
            when :many_to_many
                q_pk = model.primary_keys_qualified
                j_table = assoc[:join_table]
                l_keys = assoc[:left_keys].map{|k| j_table.q(k)}
                r_keys = assoc[:right_keys].map{|k| j_table.q(k)}
                r_keys_vals = Hash[r_keys.zip(q_pk)]
                l_keys_vals = parent_keys.all?{|k|k.to_s.empty?} ? false : Hash[l_keys.zip(parent_keys)]

                if handler.params[:negate]
                    query.exclude(model.db[j_table].select(nil).where(r_keys_vals & l_keys_vals).exists)
                else
                    # query.qualify.join(j_table, [r_keys_vals, l_keys_vals])
                    if joins = query.opts[:join] and joins.find{|j|j.table == j_table}
                        query
                    else
                        query.qualify.left_join(j_table, r_keys_vals)
                    end.filter(l_keys_vals)
                end
            else unsupported_association
            end
        end

        def post_run
            super
            nd = node.parent.nodes[:decode_entry]
            request do |h|
                if h.initial?
                    action = nd.*
                    rec = action.invoke_decode(h, [split_keys(h.params[:parent_id])]).first
                    panel_title "#{static.panel[:title]} - #{action.meta[:decode_fields].map{|f|rec[f.to_sym]}.join(action.meta[:separator])}"
                end
            end if nd
        end
    end

    class StarToManyLinkListAction < StarToManyListAction
        action_type :star_to_many_link_list
        def pre_run
            super
            panel_title LOCS[:link_title]
            menu(:panel_menu).option_at 0, :link, icon: "ok", enabled: "action.selected_size() > 0"
            node.parent.*.menu(:menu).option_at 0, :link_list, icon: "paperclip", button_loc: false
        end
    end

    # *_to_many_field
    class StarToManyFieldAction < StarToManyListAction
        action_type :star_to_many_field

        def pre_run
            super
            modal_action false
            panel_panel_template false
        end

        def list_context query, handler
            changes = handler.param_to_json(:changes)
            model = assets[:model]
            unlinked = changes[:unlink].to_a + changes[:delete].to_a + changes[:modify].to_a.map{|m|join_keys(model.primary_keys.map{|k|m[k]})}
            linked = changes[:link]
            query = super(query, handler)

            pks = model.primary_keys_qualified

            if handler.params[:negate]
                query = unlinked.reduce(query){|q, unl|q.or pks.zip(split_keys(unl))}
                query = linked.reduce(query){|q, ln|q.where(pks.zip(split_keys(ln)).sql_negate)}
            else
                query = unlinked.reduce(query){|q, unl|q.where(pks.zip(split_keys(unl)).sql_negate)}
                query = case assets[:assoc][:type]
                when :one_to_many
                    linked.reduce(query){|q, ln|q.or pks.zip(split_keys(ln))}
                when :many_to_many
                    linked.reduce(query){|q, ln|q.or pks.zip(split_keys(ln))}.distinct
                else unsupported_association
                end unless linked.empty?
            end

            added = changes[:create].to_a + changes[:modify].to_a
            cols = get_query.columns
            query = added.reduce query do |q, a|
                q.union(model.db.select(*cols.map{|c|a[c]}), all: true, alias: model.table_name)
            end

            query
        end
    end

    class StarToManyFieldLinkListAction < StarToManyFieldAction
        action_type :star_to_many_field_link_list

        def pre_run
            super
            modal_action true
            panel_panel_template nil
            panel_title LOCS[:link_title]
            menu(:panel_menu).option_at 0, :link, icon: "ok", enabled: "action.selected_size() > 0"
            node.parent.*.menu(:menu).option_at 0, :link_list, icon: "paperclip", button_loc: false
        end
    end
end
