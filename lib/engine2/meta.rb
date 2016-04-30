# coding: utf-8
module Engine2
    class Meta
        attr_reader :action, :assets, :invokable, :static

        class << self
            def meta_type mt = nil
                mt ? @meta_type = mt : @meta_type
            end

            def http_method hm = nil
                hm ? @http_method = hm : @http_method
            end

            def inherited cls
                cls.http_method http_method
            end
        end

        http_method :get

        def initialize action, assets, static = self
            @meta = {}
            @action = action
            @assets = assets
            @static = static
        end

        # def self.method_added name
        #     puts "ADDED #{name}"
        # end

        def http_method
            @http_method # || (raise E2Error.new("No http method for meta #{self.class}"))
        end

        def meta_type
            @meta_type || (raise E2Error.new("No meta_type for meta #{self.class}"))
        end

        def check_static_meta
            raise E2Error.new("Static meta required") if dynamic?
        end

        def invoke! handler
            if rmp = @request_meta_proc
                meta = self.class.new(action, assets, self)
                meta.instance_exec(handler, *meta.request_meta_proc_params(handler), &rmp)
                meta.post_process

                {response: meta.invoke(handler), meta: meta.get}
            else
                response = invoke(handler)
                if response.is_a?(Hash)
                    {response: response}
                else
                    response
                end
            end
        end

        def response args
            (@meta[:response] ||= {}).merge!(args)
        end

        def get
            @meta
        end

        def dynamic?
            self != @static
        end

        # def [] *keys
        #     @meta.path(*keys)
        # end

        # def []= *keys, value
        #     @meta.path!(*keys, value)
        # end

        def lookup *keys
            if dynamic? # we are the request meta
                value = @meta.path(*keys)
                value.nil? ? @static.get.path(*keys) : value
                # value || @static.value.path(keys)
            else
                @meta.path(*keys)
            end
        end

        def merge *keys
            if keys.length == 1
                key = keys.first
                dynamic? ? @static.get[key].merge(@meta[key] || {}) : @meta[key]
            else
                dynamic? ? @static.get.path(*keys).merge(@meta.path(*keys)) : @meta.path(*keys)
            end
        end

        def freeze_meta
            hash = @meta
            hash.freeze
            # hash.each_pair{|k, v| freeze(v) if v.is_a? Hash}
            freeze
        end

        def request_meta_proc_params handler
            []
        end

        def request &blk
            raise E2Error.new("No block given for request meta") unless blk
            raise E2Error.new("Request meta already supplied") if @request_meta_proc
            raise E2Error.new("No request block in request meta allowed") if dynamic?
            @request_meta_proc = blk
            nil
        end

        def pre_run
            @meta_type = self.class.meta_type
            @http_method = self.class.http_method
        end

        def action_defined
        end

        def post_run
            @invokable = respond_to?(:invoke)
            post_process
        end

        def post_process
        end

        def split_keys id
            Sequel::split_keys(id)
        end
    end

    class DummyMeta < Meta
        meta_type :dummy

        # def invoke handler
        #     {}
        # end
    end

    module MetaAPISupport
        def info
            @meta[:info] ||= {}
        end

        def config
            @meta[:config] ||= {}
        end

        def info! *fields, options
            raise E2Error.new("No fields given to info") if fields.empty?
            fields.each do |field|
                if options
                    (info[field] ||= {}).merge! options # rmerge ?
                else
                    info[field] = false
                end
            end
        end

        def loc! hash
            hash.each{|k, v| info! k, loc: v}
        end

        def decorate list
            list.each do |f|
                m = (info[f] ||= {})
                m[:loc] ||= LOCS[f]
            end
        end

        def render field, options
            info! field, render: options
        end

        def hide_fields *flds
            info! *flds, hidden: true
        end

        def show_fields *flds
            info! *flds, hidden: false
        end

        def field_filter *flds, filter
            info! *flds, filter: filter
        end
    end

    module MetaMenuSupport
        def menu menu_name, &blk
            @menus ||= {}
            @menus[menu_name] ||= ActionMenuBuilder.new(:root)
            @menus[menu_name].instance_eval(&blk) if blk
            @menus[menu_name]
        end

        def post_process
            super
            if @menus && !@menus.empty?
                @meta[:menus] = {}
                @menus.each_pair do |name, menu|
                    @meta[:menus][name] = {entries: menu.to_a, properties: menu.properties}
                end
            end
        end
    end

    module MetaModelSupport
        def pre_run
            if !(mdl = @assets[:model])
                act = action
                begin
                    act = act.parent
                    raise E2Error.new("Model not found in tree for action: #{action.name}") unless act
                    mdl = act.*.assets[:model]
                end until mdl

                if asc = @assets[:assoc]
                    @assets[:model] = Object.const_get(asc[:class_name])
                    # raise E2Error.new("Association '#{asc}' for model '#{asc[:class_name]}' not found") unless @assets[:model]
                else
                    @assets[:model] = mdl
                    asc = act.*.assets[:assoc]
                    @assets[:assoc] = asc if asc
                end
            end

            # @meta[:model!] = assets[:model]
            # @meta[:assoc!] = assets[:assoc] ? assets[:assoc][:name] : nil
            # @meta[:meta_class!] = self.class
            super
        end

        def hide_pk
            hide_fields *assets[:model].primary_keys
        end

        def show_pk
            show_fields *assets[:model].primary_keys
        end

        def get_type_info name
            model = assets[:model]
            info = model.type_info[name]
            unless info
                if name =~ /^(\w+)__(\w+?)$/ # (?:___\w+)?
                    assoc = model.many_to_one_associations[$1.to_sym] || model.one_to_one_associations[$1.to_sym]
                    raise E2Error.new("Association #{$1} not found for model #{model}") unless assoc
                    m = Object.const_get(assoc[:class_name])
                    info = m.type_info.fetch($2.to_sym)
                else
                    raise E2Error.new("Type info not found for '#{name}' in model '#{model}'")
                end
            end
            info
        end

        # def parent_model_name
        #     model = @assets[:model]
        #     prnt = action.parent

        #     while prnt && prnt.*.assets[:model] == model
        #         prnt = prnt.parent
        #     end
        #     m = prnt.*.assets[:model]
        #     m ? m.name : nil
        # end

        def action_defined
            super
            # p_model_name = parent_model_name
            model = @assets[:model]

            mt = meta_type
            case mt
            when :list, :star_to_many_list, :star_to_many_link_list, :star_to_many_field, :star_to_many_field_link_list # :many_to_one_list
                model.many_to_one_associations.each do |assoc_name, assoc|
                    unless assoc[:propagate] == false # || p_model_name == assoc[:class_name]
                        dc = model.type_info[assoc[:keys].first][:decode]
                        action.run_scheme :decode, model, assoc_name, dc[:search]
                    end
                end
            end

            case mt
            when :modify, :create
                model.many_to_one_associations.each do |assoc_name, assoc|
                    unless assoc[:propagate] == false # || p_model_name == assoc[:class_name]
                        dc = model.type_info[assoc[:keys].first][:decode]
                        action.run_scheme :decode, model, assoc_name, dc[:form]
                    end
                end
            end

            case mt
            when :list #, :star_to_many_list, :many_to_one_list # list dropdowns
                divider = false
                model.one_to_many_associations.merge(model.many_to_many_associations).each do |assoc_name, assoc|
                    unless assoc[:propagate] == false
                        menu(:item_menu).divider unless divider
                        divider ||= true
                        menu(:item_menu).option :"#{assoc_name}!", icon: "list" # , click: "action.show_assoc($index, \"#{assoc_name}!\")"
                        action.run_scheme :star_to_many, :"#{assoc_name}!", assoc
                    end
                end
            end

            case mt
            when :modify, :create
                model.type_info.each do |field, info|
                    case info[:type]
                    when :blob_store
                        action.run_scheme :blob_store, model, field
                    when :foreign_blob_store
                        action.run_scheme :foreign_blob_store, model, field
                    when :file_store
                        action.run_scheme :file_store, model, field
                    when :star_to_many_field
                        assoc = model.association_reflections[info[:assoc_name]] # info[:name] ?
                        raise E2Error.new("Association '#{info[:assoc_name]}' not found for model '#{model}'") unless assoc
                        action.run_scheme :star_to_many_field, assoc, field
                    end
                end
            end
        end

        def unsupported_association assoc
            raise E2Error.new("Unsupported association: #{assoc}")
        end
    end

    module MetaQuerySupport
        def query q, &blk
            @query = q.naked
            @query.row_proc = blk if blk
        end

        def post_run
            query select(*assets[:model].columns) unless @query
            super
        end

        def get_query # move to query ?
            if dynamic?
                @query || @static.get_query
            else
                @query
            end
        end

        def select *args, &blk
            assets[:model].select(*args, &blk).ensure_primary_key.setup! (@meta[:fields] = [])
        end
    end

    module MetaTabSupport
        def select_tabs tabs, *args, &blk
            field_tabs tabs
            select *tabs.map{|name, fields|fields}.flatten, *args, &blk
        end

        def field_tabs hash
            @meta[:tabs] = hash.map{|k, v| {name: k, loc: LOCS[k], fields: v} }
        end

        def lazy_tab tab_name
           tabs = @meta[:tabs]
           raise E2Error.new("No tabs defined") unless tabs
           tab = tabs.find{|t| t[:name] == tab_name}
           raise E2Error.new("No tab #{tab_name} defined") unless tab
           tab[:lazy] = true
        end
    end

    module MetaAngularSupport
        def ng_execute expr
            (@meta[:execute] ||= "") << expr + ";"
        end

        def ng_record! name, value
            value = case value
            when String
                "'#{value}'"
            when nil
                'null'
            else
                value
            end

            "action.record['#{name}'] = #{value}"
        end

        def ng_record name
            "action.record['#{name}']"
        end

        def ng_info! name, *selector, expression
            # expression = "'#{expression}'" if expression.is_a? String
            "action.meta.info['#{name}'].#{selector.join('.')} = #{expression}"
        end

        def ng_call name, *args
            # TODO
        end
    end

    module MetaPanelSupport
        def pre_run
            modal_action true
            super
        end

        def post_run
            super
            if @meta[:panel]
                panel_panel_template 'menu_m' unless panel[:panel_template] == false
                # modal_action false if panel[:panel_template] == false
                panel_class '' unless panel[:class]
            end
        end

        def glyphicon name
            "<span class='glyphicon glyphicon-#{name}'></span>"
        end

        def panel
            @meta[:panel] ||= {}
        end

        def modal_action modal = true
            panel[:modal_action] = modal
        end

        def panel_template tmpl
            panel[:template] = tmpl
        end

        def panel_panel_template tmpl
            panel[:panel_template] = tmpl
        end

        def panel_class cls
            panel[:class] = cls
        end

        def panel_title tle
            panel[:title] = tle
        end
    end

    class MenuMeta < Meta
        include MetaMenuSupport
        meta_type :menu

        def invoke handler
            {}
        end
    end

    class ConfirmMeta < Meta
        include MetaPanelSupport, MetaMenuSupport
        meta_type :confirm

        def pre_run
            super
            panel_template 'scaffold/message'
            panel_title LOCS[:confirmation]
            panel_class 'modal-default'

            menu :panel_menu do
                option :approve, icon: "ok", loc: LOCS[:ok], disabled: 'action.action_pending'
                option :cancel, icon: "remove"
            end
        end

        def invoke handler
            params = handler.request.params
            # params.merge({arguments: params.keys})
        end
    end

    module MetaOnChangeSupport
        def on_change field, &blk
            action_name = :"#{field}_on_change"
            act = action.define_action action_name, (blk.arity > 2 ? OnChangeGetMeta : OnChangePostMeta)
            act.*{request &blk}

            info! field, remote_onchange: action_name
            info! field, remote_onchange_record: :true if blk.arity > 2
        end

        class OnChangeMeta < Meta
            include MetaAPISupport, MetaAngularSupport

            def request_meta_proc_params handler
                if handler.request.post?
                    json = handler.post_to_json
                    [json[:value], json[:record]]
                else
                    params = handler.request.params
                    [params["value"], params["record"]]
                end
            end

            def invoke handler
                {}
            end
        end

        class OnChangeGetMeta < OnChangeMeta
            meta_type :on_change

            def request_meta_proc_params handler
                params = handler.request.params
                [params["value"], params["record"]]
            end
        end

        class OnChangePostMeta < OnChangeMeta
            http_method :post
            meta_type :on_change

            def request_meta_proc_params handler
                json = handler.post_to_json
                [json[:value], json[:record]]
            end
        end
    end

    module MetaListSupport
        include MetaModelSupport, MetaAPISupport, MetaTabSupport, MetaPanelSupport, MetaMenuSupport, MetaOnChangeSupport
        attr_reader :filters, :orders

        def pre_run
            super
            config.merge!(per_page: 10, use_count: false, show_item_menu: true, selectable: true) # search_active: false,

            # modal_action self.class != ListMeta
            panel_template 'scaffold/list'
            panel_panel_template 'panels/menu_m' unless action.parent.*.assets[:model]
            search_template 'scaffold/search'
            panel_title "#{glyphicon('list')} #{LOCS[assets[:model].name.to_sym]}"
            menu(:panel_menu).option :cancel, icon: "remove"
            menu :menu do
                properties break: 2, group_class: "btn-group-xs"
                option :search_toggle, icon: "search", show: "action.meta.search_fields", class: "action.ui_state.search_active && 'active'", button_loc: false

                # divider
                option :refresh, icon: "refresh", button_loc: false
                option :default_order, icon: "signal", button_loc: false
                option :select_toggle, icon: "check", enabled: "action.meta.config.selectable", button_loc: false
                divider
                option :debug_info, icon: "list-alt" do
                    option :show_meta, icon: "eye-open"
                end
            end

            menu :item_menu do
                properties break: 1, group_class: "btn-group-xs"
            end

            @meta[:state] = [:query, :ui_state]
        end

        def post_run
            unless panel[:class]
                panel_class case @meta[:fields].size
                when 1..3; ''
                when 4..6; 'modal-large'
                else; 'modal-huge'
                end
            end

            super
            @meta[:primary_fields] = assets[:model].primary_keys
        end

        # def find_renderer type_info
        #     renderer = DefaultSearchRenderers[type_info[:type]] || DefaultSearchRenderers[type_info[:otype]]
        #     raise E2Error.new("No search renderer found for field '#{type_info[:name]}'") unless renderer
        #     renderer.(self, type_info)
        # end

        def post_process
            if fields = @meta[:search_fields]
                fields = fields - static.get[:search_fields] if dynamic?

                decorate(fields)
                fields.each do |name|
                    type_info = get_type_info(name)

                    # render = info[name][:render]
                    # if not render
                    #     info[name][:render] = find_renderer(type_info)
                    # else
                    #     info[name][:render].merge!(find_renderer(type_info)){|key, v1, v2|v1}
                    # end

                    info[name][:render] ||= begin # set before :fields
                        renderer = DefaultSearchRenderers[type_info[:type]] || DefaultSearchRenderers[type_info[:otype]]
                        raise E2Error.new("No search renderer found for field '#{type_info[:name]}'") unless renderer
                        renderer.(self, type_info)
                    end

                    proc = SearchRendererPostProcessors[type_info[:type]] || ListRendererPostProcessors[type_info[:type]] # ?
                    proc.(self, name, type_info) if proc
                end
            end

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

        def search_template template
            panel[:search_template] = template
        end

        def sortable *flds
            flds = @meta[:fields] if flds.empty?
            info! *flds, sort: true
        end

        def search_live *flds
            flds = @meta[:search_fields] if flds.empty?
            info! *flds, search_live: true
        end

        def searchable *flds
            @meta.delete(:tabs)
            @meta[:search_fields] = *flds
        end

        def searchable_tabs tabs
            searchable *tabs.map{|name, fields|fields}.flatten
            field_tabs tabs
        end

        def template
            SearchTemplates
        end

        def filter name, &blk
            (@filters ||= {})[name] = blk
        end

        def order name, &blk
            (@orders ||= {})[name] = blk
        end
    end

    module MetaApproveSupport
        include MetaModelSupport
        attr_reader :validations

        def validate_fields *fields
            if fields.empty?
                @validate_fields
            else
                @validate_fields = assets[:model].type_info.keys & (fields + assets[:model].primary_keys).uniq
            end
        end

        def before_approve handler, record
        end

        def after_approve handler, record
        end

        def validate_and_approve handler, record, json
            static.before_approve(handler, record)
            record.valid?
            validate_record(handler, record)
            if record.errors.empty?
                static.after_approve(handler, record)
                true
            else
                false
            end
        end

        def allocate_record handler, json
            model = assets[:model]
            json_rec = json[:record]
            handler.permit json_rec.is_a?(Hash)
            val_fields = (dynamic? ? static.validate_fields : @validate_fields) || model.type_info.keys
            handler.permit (json_rec.keys - val_fields).empty?

            record = model.call(json_rec)
            record.validate_fields = val_fields
            record
        end

        def record handler, record
            {errors: nil}
        end

        def invoke handler
            json = handler.post_to_json
            record = allocate_record(handler, json)
            validate_and_approve(handler, record, json) ? static.record(handler, record) : {record: record.to_hash, errors: record.errors}
        end

        def validate name, &blk
            (@validations ||= {})[name] = blk
        end

        def validate_record handler, record
            @validations.each do |name, val|
                unless record.errors[name]
                    result = val.(record, handler)
                    record.errors.add(name, result) if result
                end
            end if @validations
        end

        def post_run
            super
            validate_fields *action.parent.*.get[:fields] unless validate_fields
        end
    end

    module MetaViewSupport
        include MetaModelSupport, MetaAPISupport, MetaTabSupport, MetaPanelSupport, MetaMenuSupport

        def pre_run
            super
            panel_template 'scaffold/view'
            panel_title LOCS[:view_title]

            menu(:panel_menu).option :cancel, icon: "remove"
            action.parent.*.menu(:item_menu).option action.name, icon: "file", button_loc: false
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

    module DeleteMetaSupport
        include MetaModelSupport

        def pre_run
            super
            action.parent.parent.*.menu(:item_menu).option :confirm_delete, icon: "trash", show: "action.selected_size() == 0", button_loc: false
        end
    end

    module BulkDeleteMetaSupport
        include MetaModelSupport

        def pre_run
            super
            action.parent.parent.*.menu(:menu).option_after :default_order, :confirm_bulk_delete, icon: "trash", show: "action.selected_size() > 0"
        end
    end

    (FormRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|meta, field, info|
            meta.info[field][:render].merge! true_value: info[:true_value], false_value: info[:false_value]
            meta.info[field][:dont_strip] = info[:dont_strip] if info[:dont_strip]
        },
        date: lambda{|meta, field, info|
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format]
            if date_to = info[:other_date]
                meta.info[field][:render].merge! other_date: date_to #, format: info[:format], model_format: info[:model_format]
                meta.hide_fields date_to
            elsif time = info[:other_time]
                meta.info[field][:render].merge! other_time: time
                meta.hide_fields time
            end
        },
        time: lambda{|meta, field, info|
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format]
        },
        decimal_date: lambda{|meta, field, info|
            FormRendererPostProcessors[:date].(meta, field, info)
            meta.info! field, type: :decimal_date
        },
        decimal_time: lambda{|meta, field, info|
            FormRendererPostProcessors[:time].(meta, field, info)
            meta.info! field, type: :decimal_time
        },
        datetime: lambda{|meta, field, info|
            meta.info[field][:render].merge! date_format: info[:date_format], time_format: info[:time_format], date_model_format: info[:date_model_format], time_model_format: info[:time_model_format]
        },
        # date_range: lambda{|meta, field, info|
        #     meta.info[field][:render].merge! other_date: info[:other_date], format: info[:format], model_format: info[:model_format]
        #     meta.hide_fields info[:other_date]
        #     meta.info[field][:decimal_date] = true if info[:validations][:decimal_date]
        # },
        list_select: lambda{|meta, field, info|
            meta.info[field][:render].merge! list: info[:list]
        },
        many_to_one: lambda{|meta, field, info|
            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = info[:keys]
            field_info[:type] = info[:otype]
            # field_info[:table_loc] = LOCS[info[:assoc_name]]

            (info[:keys] - [field]).each do |of|
                f_info = meta.info.fetch(of)
                f_info[:hidden] = true
                f_info[:type] = meta.assets[:model].type_info[of].fetch(:otype)
            end
        },
        file_store: lambda{|meta, field, info|
            meta.info[field][:render].merge! multiple: info[:multiple]
            # meta[:model] = meta.action.model.table_name
        },
        star_to_many_field: lambda{|meta, field, info|
            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            # meta.info[field][:render].merge! multiple: info[:multiple]
            # field_info = meta.info[field]
            # field_info[:resource] ||= "#{Handler::API}#{meta.model.namespace}/#{info[:assoc_name]}"
        }
    )

    (ListRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|meta, field, info|
            meta.info! field, type: :boolean # move to meta ?
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! true_value: info[:true_value], false_value: info[:false_value]
        },
        list_select: lambda{|meta, field, info|
            meta.info! field, type: :list_select
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! list: info[:list]
        },
        datetime: lambda{|meta, field, info|
            meta.info! field, type: :datetime
        },
        decimal_date: lambda{|meta, field, info|
            meta.info! field, type: :decimal_date
        },
        decimal_time: lambda{|meta, field, info|
            meta.info! field, type: :decimal_time
        },
        # date_range: lambda{|meta, field, info|
        #     meta.info[field][:type] = :decimal_date if info[:validations][:decimal_date] # ? :decimal_date : :date
        # }
    )

    (SearchRendererPostProcessors ||= {}).merge!(
        many_to_one: lambda{|meta, field, info|
            model = meta.assets[:model]
            if model.type_info[field]
                keys = info[:keys]
            else
                meta.check_static_meta
                model = Object.const_get(model.many_to_one_associations[field[/^\w+?(?=__)/].to_sym][:class_name])
                # meta.action.define_action :"#{info[:assoc_name]}!" do # assoc_#{aname}
                #     define_action :decode, DecodeEntryMeta, assoc: model.association_reflections[info[:assoc_name]] do
                #         run_scheme :default_many_to_one
                #     end
                # end

                # verify associations ?
                # model = Model.models.fetch(field[/^\w+?(?=__)/].to_sym)
                keys = info[:keys].map{|k| :"#{model.table_name}__#{k}"}
            end

            field_info = meta.info[field]
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = keys
            field_info[:type] = info[:otype]
            # field_info[:table_loc] = LOCS[info[:assoc_name]]

            (keys - [field]).each do |of|
                f_info = meta.info[of]
                raise E2Error.new("Missing searchable field: '#{of}' in model '#{meta.assets[:model]}'") unless f_info
                f_info[:hidden_search] = true
                f_info[:type] = model.type_info[of].fetch(:otype)
            end
        },
        date: lambda{|meta, field, info|
            meta.info[field][:render] ||= {}
            meta.info[field][:render].merge! format: info[:format], model_format: info[:model_format] # Model::DEFAULT_DATE_FORMAT
        },
        decimal_date: lambda{|meta, field, info|
            SearchRendererPostProcessors[:date].(meta, field, info)
        }
    )

    (DefaultFormRenderers ||= {}).merge!(
        date: lambda{|meta, info|
            info[:other_date] ? Templates.date_range : (info[:other_time] ? Templates.date_time : Templates.date_picker)

        },
        time: lambda{|meta, info| Templates.time_picker},
        datetime: lambda{|meta, info| Templates.datetime_picker},
        file_store: lambda{|meta, info| Templates.file_store},
        blob: lambda{|meta, info| Templates.blob}, # !!!
        blob_store: lambda{|meta, info| Templates.blob},
        foreign_blob_store: lambda{|meta, info| Templates.blob},
        string: lambda{|meta, info| Templates.input_text(info[:length])},
        text: lambda{|meta, info| Templates.text},
        integer: lambda{|meta, info| Templates.integer},
        decimal: lambda{|meta, info| Templates.decimal},
        decimal_date: lambda{|meta, info| DefaultFormRenderers[:date].(meta, info)},
        decimal_time: lambda{|meta, info| Templates.time_picker},
        email: lambda{|meta, info| Templates.email(info[:length])},
        password: lambda{|meta, info| Templates.password(info[:length])},
        # date_range: lambda{|meta, info| Templates.date_range},
        boolean: lambda{|meta, info| Templates.checkbox_buttons(optional: !info[:required])},
        currency: lambda{|meta, info| Templates.currency},
        list_select: lambda{|meta, info|
            length = info[:list].length
            if length <= 3
                Templates.list_buttons(optional: !info[:required])
            elsif length <= 15
                max_length = info[:list].max_by{|a|a.last.length}.last.length
                Templates.list_bsselect(max_length, optional: !info[:required])
            else
                max_length = info[:list].max_by{|a|a.last.length}.last.length
                Templates.list_select(max_length, optional: !info[:required])
            end
        },
        star_to_many_field: lambda{|meta, info| Templates.scaffold},
        many_to_one: lambda{|meta, info| # Templates.scaffold_picker
            tmpl_type = info[:decode][:form]
            case
            when tmpl_type[:scaffold]; Templates.scaffold_picker
            when tmpl_type[:list];     Templates.bsselect_picker
            when tmpl_type[:typeahead];Templates.typeahead_picker
            else
                raise E2Error.new("Unknown decode type #{tmpl_type}")
            end
        }, # required/opt
    )

    (DefaultSearchRenderers ||= {}).merge!(
        date: lambda{|meta, info| SearchTemplates.date_range},
        decimal_date: lambda{|meta, info| SearchTemplates.date_range},
        integer: lambda{|meta, info| SearchTemplates.integer_range},
        string: lambda{|meta, info| SearchTemplates.input_text},
        boolean: lambda{|meta, info| SearchTemplates.checkbox_buttons},
        list_select: lambda{|meta, info|
            length = info[:list].length
            if length <= 3
                SearchTemplates.list_buttons
            elsif length <= 15
                # max_length = info[:list].max_by{|a|a.last.length}.last.length
                SearchTemplates.list_bsselect(multiple: info[:multiple])
            else
                # max_length = info[:list].max_by{|a|a.last.length}.last.length
                SearchTemplates.list_select
            end
        },
        many_to_one: lambda{|meta, info|
            tmpl_type = info[:decode][:search]
            case
            when tmpl_type[:scaffold]; SearchTemplates.scaffold_picker(multiple: tmpl_type[:multiple])
            when tmpl_type[:list];     SearchTemplates.bsselect_picker(multiple: tmpl_type[:multiple])
            when tmpl_type[:typeahead];SearchTemplates.typeahead_picker
            else
                raise E2Error.new("Unknown decode type #{tmpl_type}")
            end
        }
    )
end
