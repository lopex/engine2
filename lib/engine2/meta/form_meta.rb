# coding: utf-8

module Engine2
    class FormMeta < Meta
        include MetaAPISupport, MetaModelSupport, MetaQuerySupport, MetaTabSupport, MetaPanelSupport, MetaMenuSupport, MetaAngularSupport, MetaOnChangeSupport

        def field_template template
            panel[:field_template] = template
        end

        def pre_run
            super
            panel_template 'scaffold/form'
            field_template 'scaffold/fields'
            panel_class 'modal-large'

            menu :panel_menu do
                option :approve, icon: "ok", disabled: 'action.action_pending' # text: true,
                option :cancel, icon: "remove" # text: true,
            end
            # modal_action false
        end

        def record handler, record
        end

        def post_process
            if fields = @meta[:fields]
                fields = fields - static.get[:fields] if dynamic?

                decorate(fields)

                fields.each do |name|
                    # type_info = model.type_info.fetch(name)
                    type_info = get_type_info(name)

                    info[name][:render] ||= begin
                        renderer = DefaultFormRenderers[type_info[:type]] # .merge(default: true)
                        raise E2Error.new("No form renderer found for field '#{type_info[:name]}' of type '#{type_info[:type]}'") unless renderer
                        renderer.(self, type_info)
                    end

                    proc = FormRendererPostProcessors[type_info[:type]]
                    proc.(self, name, type_info) if proc
                end

                assoc = assets[:assoc]
                if assoc && assoc[:type] == :one_to_many
                    # fields.select{|f| assoc[:keys].include? f}.each do |key|
                    #     # hide_fields(key) if self[:info, key, :hidden] == nil
                    #     info! key, disabled: true
                    # end
                    assoc[:keys].each do |key|
                        info! key, disabled: true if fields.include? key
                    end
                end
            end

            super
        end

        def post_run
            super
            @meta[:primary_fields] = assets[:model].primary_keys
        end

        def template
            Templates
        end

        def hr_after field, message = '-'
            info! field, hr: message
        end
    end

    class CreateMeta < FormMeta
        meta_type :create

        def pre_run
            super
            panel_title LOCS[:create_title]
            action.parent.*.menu(:menu).option_at 0, :create, icon: "plus-sign", button_loc: false

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
                handler.permit parent = handler.params[:parent_id]
                assoc[:keys].zip(split_keys(parent)).each do |key, val|
                    # record[key] ||= val # = ? edit/create
                    record[key] = val
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
            action.parent.*.menu(:item_menu).option :modify, icon: "pencil", button_loc: false
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
