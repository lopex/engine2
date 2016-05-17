# coding: utf-8

module Engine2
    class ViewMeta < Meta
        include MetaViewSupport, MetaQuerySupport

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
    end
end
