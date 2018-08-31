# coding: utf-8
# frozen_string_literal: true

module Engine2
    class Action
        attr_reader :node, :meta, :assets, :static, :invokable

        class << self
            def action_type at = nil
                at ? @action_type = at : @action_type
            end

            def http_method hm = nil
                hm ? @http_method = hm : @http_method
            end

            def inherited cls
                cls.http_method http_method
            end

            def inherit &blk
                cls = Class.new self do
                    action_type superclass.action_type
                end

                cls.instance_eval &blk if block_given?
                cls
            end
        end

        http_method :get

        def initialize node, assets, static = self
            @meta = {}
            @node = node
            @assets = assets
            @static = static
        end

        def http_method
            @http_method # || (raise E2Error.new("No http method for action #{self.class}"))
        end

        def action_type
            @action_type || (raise E2Error.new("No action_type for action #{self.class}"))
        end

        def check_static_action
            raise E2Error.new("Static action required") if dynamic?
        end

        def check_anonymous_action_class name
            raise E2Error.new("Defining method '#{name}'' for named class '#{self.class}', consider using #inherit") if self.class.name
        end

        def define_method name, &blk
            check_anonymous_action_class name
            self.class.class_eval{define_method name, &blk}
        end

        def define_invoke &blk
            check_static_action
            define_method :invoke, &blk
            # self.class.class_eval{define_method :invoke, &blk}
        end

        def invoke! handler
            if rmp = @request_action_proc
                action = self.class.new(node, assets, self)
                result = action.instance_exec(handler, *action.request_action_proc_params(handler), &rmp)
                action.post_process
                response = @requestable ? (result || {}) : action.invoke(handler)
                response[:meta] = action.meta
                response
            else
                invoke(handler)
            end
        end

        def repeat time
            @meta[:repeat] = time
        end

        def arguments args
            @meta[:arguments] = args
        end

        def execute command
            (@meta[:execute] ||= []) << command
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
            if dynamic? # we are the request action
                value = @meta.path(*keys)
                value.nil? ? @static.meta.path(*keys) : value
                # value || @static.value.path(keys)
            else
                @meta.path(*keys)
            end
        end

        def merge *keys
            if keys.length == 1
                key = keys.first
                dynamic? ? @static.meta[key].merge(@meta[key] || {}) : @meta[key]
            else
                dynamic? ? @static.meta.path(*keys).merge(@meta.path(*keys)) : @meta.path(*keys)
            end
        end

        def freeze_action
            hash = @meta
            hash.freeze
            # hash.each_pair{|k, v| freeze(v) if v.is_a? Hash}
            freeze
        end

        def request_action_proc_params handler
            []
        end

        def request &blk
            raise E2Error.new("No block given for request action") unless blk
            raise E2Error.new("No request block in request action allowed") if dynamic?
            @request_action_proc = @request_action_proc ? @request_action_proc.chain_args(&blk) : blk
            nil
        end

        def pre_run
            @action_type = self.class.action_type
            @http_method = self.class.http_method
        end

        def node_defined
        end

        def post_run
            if respond_to? :invoke
                @invokable = true
            else
                if @request_action_proc
                    @invokable = true
                    @requestable = true
                else
                    @meta[:invokable] = false
                end
            end
            @meta[:dynamic_meta] = true if @request_action_proc
            post_process
        end

        def post_process
        end

        def split_keys id
            Sequel::split_keys(id)
        end
    end

    module ActionWebSocketSupport
        WS_METHODS ||= Faye::WebSocket::API::TYPES.keys.map(&:to_sym)
        WS_METHODS.each do |method|
            define_method :"ws_#{method}" do |&blk|
                @ws_methods[method] = blk
            end
        end

        def pre_run
            super
            @ws_methods = {}
            @meta[:websocket] = {options: {}}
        end

        def ws_options opts
           @meta[:websocket][:options].merge! opts
        end

        def ws_execute execute
            (@meta[:websocket][:execute] ||= {}).merge! execute
        end

        def post_run
            super
            @invokable = true
        end

        def invoke! handler
            if Faye::WebSocket.websocket?(handler.env)
                ws = Faye::WebSocket.new(handler.env)
                @ws_methods.each do |method, blk|
                    ws.on(method) do |evt|
                        begin
                            data = method == :message ? JSON.parse(evt.data, symbolize_names: true) : evt
                            action = self.class.new(node, assets, self)
                            result = action.instance_exec(data, ws, evt, &blk)
                            result = {} unless result.is_a?(Hash)
                            result[:meta] = action.meta
                            ws.send! result unless action.meta.empty?
                        rescue Exception => e
                            ws.send! error: {exception: e, method: method}
                        end
                    end
                end
                ws.rack_response
            else
                super
            end
        end
    end

    class WebSocketAction < Action
        include ActionWebSocketSupport
    end

    class InlineAction < Action
        action_type :inline
    end

    class RootAction < Action
        def initialize *args
            super
            @meta.merge! environment: Handler::environment, application: Engine2::SETTINGS[:name], key_separator: Engine2::SETTINGS[:key_separator], ws_methods: ActionWebSocketSupport::WS_METHODS
        end
    end

    module ActionAPISupport
        def fields field
            (@meta[:fields] ||= {})[field.to_sym] ||= {}
        end

        def config
            @meta[:config] ||= {}
        end

        def fields! *fields, options
            raise E2Error.new("No fields given to info") if fields.empty?
            fields.each do |field|
                fields(field).merge! options # rmerge ?
            end
        end

        def loc! hash
            (@meta[:loc] ||= {}).merge! hash
        end

        def decorate list
            list.each do |f|
                fields(f)[:loc] ||= LOCS[f.to_sym]
            end
        end

        def render field, options
            fields! field, render: options
        end

        def hide_fields *flds
            fields! *flds, hidden: true
        end

        def show_fields *flds
            fields! *flds, hidden: false
        end

        def field_filter *flds, filter
            fields! *flds, filter: filter
        end
    end

    module ActionMenuSupport
        def menu menu_name, &blk
            @menus ||= {}
            @menus[menu_name] ||= ActionMenuBuilder.new(:root)
            @menus[menu_name].instance_eval(&blk) if blk
            @menus[menu_name]
        end

        def menu? menu_name
            @menus && @menus[menu_name]
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

    module ActionModelSupport
        def pre_run
            if !(mdl = @assets[:model])
                act = node
                begin
                    act = act.parent
                    raise E2Error.new("Model not found in tree for node: #{node.name}") unless act
                    mdl = act.*.assets[:model]
                end until mdl

                if asc = @assets[:assoc]
                    @assets[:model] = asc.associated_class
                    # raise E2Error.new("Association '#{asc}' for model '#{asc[:class_name]}' not found") unless @assets[:model]
                else
                    @assets[:model] = mdl
                    asc = act.*.assets[:assoc]
                    @assets[:assoc] = asc if asc
                end
            end

            # @meta[:model!] = assets[:model]
            # @meta[:assoc!] = assets[:assoc] ? assets[:assoc][:name] : nil
            # @meta[:action_class!] = self.class
            super
        end

        def hide_pk
            hide_fields *assets[:model].primary_keys
        end

        def show_pk
            show_fields *assets[:model].primary_keys
        end

        # def parent_model_name
        #     model = @assets[:model]
        #     prnt = node.parent

        #     while prnt && prnt.*.assets[:model] == model
        #         prnt = prnt.parent
        #     end
        #     m = prnt.*.assets[:model]
        #     m ? m.name : nil
        # end

        def node_defined
            super
            # p_model_name = parent_model_name
            model = @assets[:model]

            at = action_type
            case at
            when :list, :star_to_many_list, :star_to_many_link_list, :star_to_many_field, :star_to_many_field_link_list # :many_to_one_list
                model.many_to_one_associations.each do |assoc_name, assoc|
                    unless assoc[:propagate] == false # || p_model_name == assoc[:class_name]
                        dc = model.type_info[assoc[:keys].first][:decode]
                        node.run_scheme :decode, model, assoc_name, dc[:search]
                    end
                end
            end

            case at
            when :modify, :create
                model.many_to_one_associations.each do |assoc_name, assoc|
                    unless assoc[:propagate] == false # || p_model_name == assoc[:class_name]
                        dc = model.type_info[assoc[:keys].first][:decode]
                        node.run_scheme :decode, model, assoc_name, dc[:form]
                    end
                end
            end

            case at
            when :list #, :star_to_many_list, :many_to_one_list # list dropdowns
                divider = false
                model.one_to_many_associations.merge(model.many_to_many_associations).each do |assoc_name, assoc|
                    unless assoc[:propagate] == false
                        menu(:item_menu).divider unless divider
                        divider ||= true
                        menu(:item_menu).option :"#{assoc_name}!", icon: "list" # , click: "action.show_assoc($index, \"#{assoc_name}!\")"
                        node.run_scheme :star_to_many, :"#{assoc_name}!", assoc
                    end
                end
            end

            case at
            when :modify, :create
                model.type_info.each do |field, info|
                    case info[:type]
                    when :blob_store
                        node.run_scheme :blob_store, model, field
                    when :foreign_blob_store
                        node.run_scheme :foreign_blob_store, model, field
                    when :file_store
                        node.run_scheme :file_store, model, field
                    when :star_to_many_field
                        assoc = model.association_reflections[info[:assoc_name]] # info[:name] ?
                        raise E2Error.new("Association '#{info[:assoc_name]}' not found for model '#{model}'") unless assoc
                        node.run_scheme :star_to_many_field, assoc, field
                    end
                end
            end
        end

        def unsupported_association assoc
            raise E2Error.new("Unsupported association: #{assoc}")
        end
    end

    module ActionQuerySupport
        def query q, &blk
            @query = blk ? q.naked.with_row_proc(blk) : q.naked
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

        def find_record handler, id
            get_query.load assets[:model].primary_keys_hash_qualified(split_keys(id))
        end

        def select *args, use_pk: true, &blk
            ds = assets[:model].select(*args, &blk)
            ds = ds.ensure_primary_key if use_pk
            ds.setup_query(@meta[:field_list] = [])
        end
    end

    module ActionTabSupport
        def select_tabs tabs, *args, &blk
            field_tabs tabs
            select *tabs.map{|name, fields|fields}.flatten, *args, &blk
        end

        def field_tabs hash
            @meta[:tab_list] = hash.keys
            @meta[:tabs] = hash.reduce({}){|h, (k, v)| h[k] = {name: k, loc: LOCS[k], field_list: v}; h}
        end

        def tab *tabs, options
            raise E2Error.new("No tabs given to info") if tabs.empty?
            tabs.each do |tab|
                @meta[:tabs][tab].merge! options # rmerge ?
            end
        end
    end

    module ActionAngularSupport
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
            "action.meta.fields['#{name}'].#{selector.join('.')} = #{expression}"
        end

        def ng_call name, *args
            # TODO
        end
    end

    module ActionPanelSupport
        def pre_run
            modal_action true
            super
        end

        def post_run
            super
            if @meta[:panel]
                panel_panel_template 'menu_m' if panel[:panel_template].nil?
                # modal_action false if panel[:panel_template] == false
                panel_class '' unless panel[:class]
                panel_footer true if panel[:footer] != false && menu?(:panel_menu)
                panel_header true if panel[:header] != false
            end
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

        def panel_header hdr
            panel[:header] = hdr
        end

        def panel_footer ftr
            panel[:footer] = ftr
        end
    end

    module ActionDraggableSupport
        def draggable
            @meta[:draggable] ||= {}
        end

        def post_run
            super
            draggable[:position_field] ||= 'position' if @meta[:draggable]
        end
    end

    class MenuAction < Action
        include ActionMenuSupport
        action_type :menu

        def invoke handler
            {}
        end
    end

    class ConfirmAction < Action
        include ActionPanelSupport, ActionMenuSupport
        action_type :confirm

        def message msg
            @meta[:message] = msg
        end

        def pre_run
            super
            panel_template 'scaffold/message'
            panel_title LOCS[:confirmation]
            panel_class 'modal-default'

            menu :panel_menu do
                option :approve, icon: "ok", loc: LOCS[:ok], disabled: "action.action_pending()"
                option :cancel, icon: "remove"
            end
        end

        def invoke handler
            params = handler.request.params
            # params.merge({arguments: params.keys})
        end
    end

    module ActionOnChangeSupport
        def on_change field, &blk
            node_name = :"#{field}_on_change"
            nd = node.define_node node_name, (blk.arity > 2 ? OnChangeGetAction : OnChangePostAction)
            nd.*{request &blk}

            fields! field, remote_onchange: node_name
            fields! field, remote_onchange_record: :true if blk.arity > 2
        end

        class OnChangeAction < Action
            include ActionAPISupport, ActionAngularSupport

            def request_action_proc_params handler
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

        class OnChangeGetAction < OnChangeAction
            action_type :on_change

            def request_action_proc_params handler
                params = handler.request.params
                [params["value"], params["record"]]
            end
        end

        class OnChangePostAction < OnChangeAction
            http_method :post
            action_type :on_change

            def request_action_proc_params handler
                json = handler.post_to_json
                [json[:value], json[:record]]
            end
        end
    end

    module ActionListSupport
        include ActionModelSupport, ActionAPISupport, ActionTabSupport, ActionPanelSupport, ActionMenuSupport, ActionOnChangeSupport, ActionDraggableSupport
        attr_reader :filters, :orders

        def pre_run
            super
            config.merge!(per_page: 10, use_count: false, selectable: true) # search_active: false,

            panel_template 'scaffold/list'
            panel_title "#{:list.icon} #{LOCS[assets[:model].name.to_sym]}"
            loc! LOCS[:list_locs]
            menu :menu do
                properties break: 2, group_class: "btn-group-xs"
                option :search_toggle, icon: "search", show: "action.meta.search_field_list", active: "action.ui_state.search_active", button_loc: false
                # divider
                option :refresh, icon: "refresh", button_loc: false
                option :default_order, icon: "signal", button_loc: false
                divider
                option :debug_info, icon: "list-alt" do
                    option :show_meta, icon: "eye-open"
                end if Handler::development?
            end

            menu :item_menu do
                properties break: 1, group_class: "btn-group-xs"
            end

            @meta[:state] = [:query, :ui_state]
        end

        def field_tabs hash
            super
            search_template 'scaffold/search_tabs'
        end

        def select_toggle_menu
            m = menu :menu
            unless m.option_index(:select_toggle, false)
                m.option_after :default_order, :select_toggle, icon: "check", enabled: "action.meta.config.selectable", active: "action.selection", button_loc: false
            end
        end

        def post_run
            unless panel[:class]
                panel_class case @meta[:field_list].size
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
            model = assets[:model]
            if fields = @meta[:search_field_list]
                fields = fields - static.meta[:search_field_list] if dynamic?

                decorate(fields)
                fields.each do |name|
                    type_info = model.find_type_info(name)

                    # render = fields[name][:render]
                    # if not render
                    #     fields[name][:render] = find_renderer(type_info)
                    # else
                    #     fields[name][:render].merge!(find_renderer(type_info)){|key, v1, v2|v1}
                    # end

                    fields(name)[:render] ||= begin # set before :field_list
                        renderer = DefaultSearchRenderers[type_info[:type]] || DefaultSearchRenderers[type_info[:otype]]
                        raise E2Error.new("No search renderer found for field '#{type_info[:name]}'") unless renderer
                        renderer.(self, type_info)
                    end

                    proc = SearchRendererPostProcessors[type_info[:type]] || ListRendererPostProcessors[type_info[:type]] # ?
                    proc.(self, name, type_info) if proc
                end
            end

            if fields = @meta[:field_list]
                fields = fields - static.meta[:field_list] if dynamic?

                decorate(fields)
                fields.each do |name|
                    type_info = model.find_type_info(name)
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
            flds = @meta[:field_list] if flds.empty?
            fields! *flds, sort: true
        end

        def search_live *flds
            flds = @meta[:search_field_list] if flds.empty?
            fields! *flds, search_live: true
        end

        def searchable *flds
            @meta.delete(:tab_list)
            @meta.delete(:tabs)
            search_template 'scaffold/search'
            @meta[:search_field_list] = *flds
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

        def filter_case_insensitive name
            raise E2Error.new("Field '#{name}' needs to be a string one") unless assets[:model].find_type_info(name)[:otype] == :string
            filter(name){|handler, query, hash| query.where(name.ilike("%#{hash[name]}%")) }
        end

        def order name, &blk
            (@orders ||= {})[name] = blk
        end
    end

    module ActionApproveSupport
        include ActionModelSupport
        attr_reader :validations

        def self.included action
            action.http_method :post if action.is_a? Class
        end

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

        def validate_and_approve handler, record, parent_id
            static.before_approve(handler, record)
            record.valid?
            validate_record(handler, record, parent_id)
            if record.errors.empty?
                static.after_approve(handler, record)
                true
            else
                false
            end
        end

        def allocate_record handler, json_rec
            model = assets[:model]
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
            record = allocate_record(handler, json[:record])
            validate_and_approve(handler, record, json[:parent_id]) ? static.record(handler, record) : {record!: record.to_hash, errors!: record.errors}
        end

        def validate name, &blk
            (@validations ||= {})[name] = blk
        end

        def validate_record handler, record, parent_id
            @validations.each do |name, val|
                unless record.errors[name]
                    result = val.(handler, record, parent_id)
                    record.errors.add(name, result) if result
                end
            end if @validations
        end

        def pre_run
            super
            execute "action.errors || [action.parent().invoke(), action.panel_close()]"
        end

        def post_run
            super
            validate_fields *node.parent.*.meta[:field_list] unless validate_fields
        end
    end

    module ActionSaveSupport
        include ActionApproveSupport

        def self.included action
            action.http_method :post
            class << action
                attr_accessor :validate_only
            end
        end

        def validate_and_approve handler, record, parent_id, validate_only = self.class.validate_only
            if validate_only
                super(handler, record, parent_id)
            else
                record.skip_save_refresh = true
                record.raise_on_save_failure = false
                model = assets[:model]
                assoc = assets[:assoc]
                new_assoc = record.new? && assoc && assoc[:type]

                save = lambda do |c|
                    if super(handler, record, parent_id)
                        if new_assoc == :one_to_many
                            handler.permit parent_id
                            assoc[:keys].zip(split_keys(parent_id)).each{|k, v|record[k] = v}
                        end

                        result = record.save(transaction: false, validate: false)
                        if result && new_assoc == :many_to_many
                            handler.permit parent_id
                            model.db[assoc[:join_table]].insert(assoc[:left_keys] + assoc[:right_keys], split_keys(parent_id) + record.primary_key_values)
                        end

                        model.association_reflections.each do |name, assoc|
                            hash = record[name]
                            if hash.is_a?(Hash)
                                validate_and_approve_association(handler, record, name, :create, hash)
                                validate_and_approve_association(handler, record, name, :modify, hash)
                                nd = node.parent[:"#{name}!"]
                                raise Sequel::Rollback unless record.errors.empty?
                                nd.confirm_delete.delete.*.invoke_delete_db(handler, hash[:delete].to_a, model.table_name) unless hash[:delete].to_a.empty?
                                nd.link.*.invoke_link_db(handler, record.primary_key_values, hash[:link].to_a) unless hash[:link].to_a.empty?
                                nd.confirm_unlink.unlink.*.invoke_unlink_db(handler, record.primary_key_values, hash[:unlink].to_a) unless hash[:unlink].to_a.empty?
                            end
                        end
                        result
                    end
                end
                (model.validation_in_transaction || new_assoc == :many_to_many) ? model.db.transaction(&save) : save.(nil)
            end
        end

        def validate_and_approve_association handler, record, assoc_name, node_name, hash
            records = hash[node_name].to_a
            unless records.empty?
                action = node.parent[:"#{assoc_name}!"][node_name].approve.*
                parent_id = Sequel::join_keys(record.primary_key_values)
                records.each do |arec|
                    rec = action.allocate_record(handler, arec)
                    action.validate_and_approve(handler, rec, parent_id, false)
                    rec.errors.each do |k, v|
                        (record.errors[assoc_name] ||= []).concat(v)
                    end unless rec.errors.empty?
                end
            end
        end
    end

    module ActionInsertSupport
        def allocate_record handler, json_rec
            record = super(handler, json_rec)
            record.instance_variable_set(:"@new", true)
            model = assets[:model]
            model.primary_keys.each{|k|record.values.delete k} unless model.natural_key
            handler.permit !record.has_primary_key? unless model.natural_key
            record
        end
    end

    module ActionUpdateSupport
        def allocate_record handler, json_rec
            record = super(handler, json_rec)
            model = assets[:model]
            handler.permit record.has_primary_key? unless model.natural_key or self.class.validate_only
            record
        end
    end

    module ActionFormSupport
        include ActionModelSupport, ActionAPISupport, ActionTabSupport, ActionPanelSupport, ActionMenuSupport, ActionAngularSupport, ActionOnChangeSupport

        def field_template template
            panel[:field_template] = template
        end

        def pre_run
            super
            panel_template 'scaffold/form'
            field_template 'scaffold/fields'
            panel_class 'modal-large'
            top = node.parent.parent == nil
            menu :panel_menu do
                option :approve, icon: "ok", disabled: "action.action_pending()" # text: true,
                option :cancel, icon: "remove" unless top # text: true,
            end
            # modal_action false
        end

        def field_tabs hash
            super
            panel_template 'scaffold/form_tabs'
        end

        def record handler, record
        end

        def post_process
            if fields = @meta[:field_list]
                model = assets[:model]
                fields = fields - static.meta[:field_list] if dynamic?

                decorate(fields)

                fields.each do |name|
                    type_info = model.find_type_info(name)

                    fields(name)[:render] ||= begin
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
                    #     # hide_fields(key) if self[:fields, key, :hidden] == nil
                    #     fields! key, disabled: true
                    # end
                    assoc[:keys].each do |key|
                        fields! key, disabled: true if fields.include? key
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
            fields! field, hr: message
        end
    end

    module ActionCreateSupport
        include ActionFormSupport

        def self.included action
            action.action_type :create
        end

        def pre_run
            super
            panel_title "#{LOCS[:create_title]} - #{LOCS[assets[:model].table_name]}"
            node.parent.*.menu(:menu).option_at 0, node.name, icon: "plus-sign", button_loc: false if node.parent.*.is_a?(ListAction)

            hide_pk unless assets[:model].natural_key
        end

        def record handler, record
            create_record(handler, record)
        end

        def create_record handler, record
        end

        def invoke handler
            record = {}
            # if assoc = assets[:assoc]
            #     case assoc[:type]
            #     when :one_to_many
            #         parent = handler.params[:parent_id]
            #         assoc[:keys].zip(split_keys(parent)).each{|key, val| record[key] = val} if parent
            #     end
            # end
            static.record(handler, record)
            {record: record, new: true}
        end
    end

    module ActionModifySupport
        include ActionFormSupport

        def self.included action
            action.action_type :modify
        end

        def pre_run
            super
            panel_title "#{LOCS[:modify_title]} - #{LOCS[assets[:model].table_name]}"
            node.parent.*.menu(:item_menu).option node.name, icon: "pencil", button_loc: false
        end

        def record handler, record
            modify_record(handler, record)
        end

        def modify_record handler, record
        end

        def invoke handler
            handler.permit id = handler.params[:id]
            record = find_record(handler, id)

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
                fields! key, disabled: true
            end
        end
    end

    module ActionViewSupport
        include ActionModelSupport, ActionAPISupport, ActionTabSupport, ActionPanelSupport, ActionMenuSupport

        def self.included action
            action.action_type :view
        end

        def pre_run
            super
            panel_template 'scaffold/view'
            panel_title "#{LOCS[:view_title]} - #{LOCS[assets[:model].table_name]}"
            panel[:backdrop] = true

            menu(:panel_menu).option :cancel, icon: "remove"
            node.parent.*.menu(:item_menu).option node.name, icon: "file", button_loc: false
        end

        def field_tabs hash
            super
            panel_template 'scaffold/view_tabs'
        end

        def record handler, record
        end

        def invoke handler
            handler.permit id = handler.params[:id]
            record = find_record(handler, id)
            if record
                static.record(handler, record)
                {record: record}
            else
                handler.halt_not_found LOCS[:no_entry]
            end
        end

        def post_process
            if fields = @meta[:field_list]
                model = assets[:model]
                fields = fields - static.meta[:field_list] if dynamic?

                decorate(fields)
                fields.each do |name|
                    type_info = model.find_type_info(name)
                    proc = ListRendererPostProcessors[type_info[:type]]
                    proc.(self, name, type_info) if proc
                end
            end

            super
        end
    end

    module ActionDeleteSupport
        include ActionModelSupport

        def self.included action
            action.http_method :delete
            action.action_type :delete
        end

        def pre_run
            super
            execute "action.errors || [action.parent().invoke(), action.panel_close()]"
            node.parent.parent.*.menu(:item_menu).option :confirm_delete, icon: "trash", show: "action.selected_size() == 0", button_loc: false
        end
    end

    module ActionBulkDeleteSupport
        include ActionModelSupport

        def self.included action
            action.http_method :delete
            action.action_type :bulk_delete
        end

        def pre_run
            super
            execute "action.errors || [action.parent().invoke(), action.panel_close()]"
            node.parent.parent.*.select_toggle_menu
            node.parent.parent.*.menu(:menu).option_after :default_order, :confirm_bulk_delete, icon: "trash", show: "action.selected_size() > 0"
        end
    end

    (FormRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|action, field, info|
            action.fields(field)[:render].merge! true_value: info[:true_value], false_value: info[:false_value]
            action.fields(field)[:dont_strip] = info[:dont_strip] if info[:dont_strip]
        },
        date: lambda{|action, field, info|
            action.fields(field)[:render].merge! format: info[:format], model_format: info[:model_format]
            if date_to = info[:other_date]
                action.fields(field)[:render].merge! other_date: date_to #, format: info[:format], model_format: info[:model_format]
                action.hide_fields date_to
            elsif time = info[:other_time]
                action.fields(field)[:render].merge! other_time: time
                action.hide_fields time
            end
        },
        time: lambda{|action, field, info|
            render = action.fields(field)[:render]
            render[:type] ||= info[:otype] == :string ? :string : :number
            render.merge! format: info[:format], model_format: info[:model_format]
        },
        decimal_date: lambda{|action, field, info|
            FormRendererPostProcessors[:date].(action, field, info)
            action.fields! field, type: :decimal_date
        },
        decimal_time: lambda{|action, field, info|
            FormRendererPostProcessors[:time].(action, field, info)
            action.fields! field, type: :decimal_time
        },
        datetime: lambda{|action, field, info|
            action.fields(field)[:render].merge! date_format: info[:date_format], time_format: info[:time_format], date_model_format: info[:date_model_format], time_model_format: info[:time_model_format]
        },
        currency: lambda{|action, field, info|
            action.fields(field)[:render].merge! symbol: info[:symbol]
        },
        # date_range: lambda{|action, field, info|
        #     action.fields[field][:render].merge! other_date: info[:other_date], format: info[:format], model_format: info[:model_format]
        #     action.hide_fields info[:other_date]
        #     action.fields[field][:decimal_date] = true if info[:validations][:decimal_date]
        # },
        list_select: lambda{|action, field, info|
            render = action.fields(field)[:render]
            render.merge! values: info[:values]
            render.merge! max_length: info[:max_length], max_length_html: info[:max_length_html], separator: info[:separator] if info[:multiselect]
        },
        many_to_one: lambda{|action, field, info|
            field_info = action.fields(field)
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = info[:keys]
            field_info[:type] = info[:otype]

            (info[:keys] - [field]).each do |of|
                f_info = action.fields(of)
                f_info[:hidden] = true
                f_info[:type] = action.assets[:model].type_info[of].fetch(:otype)
            end
        },
        file_store: lambda{|action, field, info|
            action.fields(field)[:render].merge! multiple: info[:multiple]
        },
        star_to_many_field: lambda{|action, field, info|
            field_info = action.fields(field)
            field_info[:assoc] = :"#{info[:assoc_name]}!"
        }
    )

    (ListRendererPostProcessors ||= {}).merge!(
        boolean: lambda{|action, field, info|
            action.fields! field, type: :boolean # move to action ?
            action.fields(field)[:render] ||= {}
            action.fields(field)[:render].merge! true_value: info[:true_value], false_value: info[:false_value]
        },
        list_select: lambda{|action, field, info|
            action.fields! field, type: :list_select
            render = (action.fields(field)[:render] ||= {})
            render.merge! values: info[:values]
            render.merge! multiselect: true if info[:multiselect]
        },
        datetime: lambda{|action, field, info|
            action.fields! field, type: :datetime
        },
        decimal_date: lambda{|action, field, info|
            action.fields! field, type: :decimal_date
        },
        decimal_time: lambda{|action, field, info|
            action.fields! field, type: :decimal_time
        },
        # date_range: lambda{|action, field, info|
        #     action.fields[field][:type] = :decimal_date if info[:validations][:decimal_date] # ? :decimal_date : :date
        # }
    )

    (SearchRendererPostProcessors ||= {}).merge!(
        many_to_one: lambda{|action, field, info|
            model = action.assets[:model]
            if model.type_info[field]
                keys = info[:keys]
            else
                action.check_static_action
                model = model.many_to_one_associations[field.table].associated_class
                keys = info[:keys].map{|k| model.table_name.q(k)}
            end

            field_info = action.fields(field)
            field_info[:assoc] = :"#{info[:assoc_name]}!"
            field_info[:fields] = keys
            field_info[:type] = info[:otype]

            (keys - [field]).each do |of|
                f_info = action.fields(of)
                raise E2Error.new("Missing searchable field: '#{of}' in model '#{action.assets[:model]}'") unless f_info
                f_info[:hidden_search] = true
                f_info[:type] = model.type_info[of].fetch(:otype)
            end
        },
        date: lambda{|action, field, info|
            action.fields(field)[:render] ||= {}
            action.fields(field)[:render].merge! format: info[:format], model_format: info[:model_format] # Model::DEFAULT_DATE_FORMAT
        },
        decimal_date: lambda{|action, field, info|
            SearchRendererPostProcessors[:date].(action, field, info)
        }
    )

    (DefaultFormRenderers ||= {}).merge!(
        date: lambda{|action, info|
            info[:other_date] ? Templates.date_range : (info[:other_time] ? Templates.date_time : Templates.date_picker)

        },
        time: lambda{|action, info| Templates.time_picker},
        datetime: lambda{|action, info| Templates.datetime_picker},
        file_store: lambda{|action, info| Templates.file_store},
        blob: lambda{|action, info| Templates.blob}, # !!!
        blob_store: lambda{|action, info| Templates.blob},
        foreign_blob_store: lambda{|action, info| Templates.blob},
        string: lambda{|action, info| Templates.input_text(info[:length])},
        text: lambda{|action, info| Templates.text},
        integer: lambda{|action, info| Templates.integer},
        decimal: lambda{|action, info| Templates.decimal},
        decimal_date: lambda{|action, info| DefaultFormRenderers[:date].(action, info)},
        decimal_time: lambda{|action, info| Templates.time_picker},
        email: lambda{|action, info| Templates.email(info[:length])},
        password: lambda{|action, info| Templates.password(info[:length])},
        # date_range: lambda{|action, info| Templates.date_range},
        boolean: lambda{|action, info| Templates.checkbox_buttons(optional: !info[:required])},
        currency: lambda{|action, info| Templates.currency},
        list_select: lambda{|action, info|
            length = info[:values].length
            max_length = info[:values].map(&:last).max_by(&:length).length
            if info[:multiselect]
                Templates.list_bsmselect(max_length)
            elsif length <= 3
                Templates.list_buttons(optional: !info[:required])
            elsif length <= 15
                Templates.list_bsselect(max_length, optional: !info[:required])
            else
                Templates.list_select(max_length, optional: !info[:required])
            end
        },
        star_to_many_field: lambda{|action, info| Templates.scaffold},
        many_to_one: lambda{|action, info|
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
        date: lambda{|action, info| SearchTemplates.date_range},
        decimal_date: lambda{|action, info| SearchTemplates.date_range},
        integer: lambda{|action, info| SearchTemplates.integer_range},
        string: lambda{|action, info| SearchTemplates.input_text},
        boolean: lambda{|action, info| SearchTemplates.checkbox_buttons},
        list_select: lambda{|action, info|
            length = info[:values].length
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
        many_to_one: lambda{|action, info|
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
