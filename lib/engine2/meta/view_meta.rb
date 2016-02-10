# coding: utf-8

module Engine2
    class ViewMeta < Meta
        include MetaQuerySupport, MetaTabSupport, MetaPanelSupport, MetaMenuSupport
        meta_type :view

        def record handler, record
        end

        def pre_run
            super
            panel_template 'scaffold/view'
            panel_title LOCS[:view_title]

            menu(:panel_menu).option :cancel, icon: "remove"
            action.parent.*.menu(:item_menu).option :view, icon: "file", button_loc: false
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

        def post_process
            if fields = @meta[:fields]
                fields = fields - static.get[:fields] if dynamic?

                decorate(fields)
                fields.each do |name|
                    type_info = get_type_info(name)
                    proc = ListRendererPostProcessors[type_info[:type]]
                    proc.(self, name, type_info) if proc
                end
            end

            super
        end
    end
end
