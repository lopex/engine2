'use strict'
angular.module('Engine2')
.directive 'e2Action', (E2Actions) ->
    scope: true
    controller: ($scope, $attrs, $parse, $element, $http) ->
        if action_attr = $attrs.action
            action_names = $parse(action_attr)($scope)
            throw "Invalid action path: '#{action_attr}'" unless action_names
            action_names = action_names.split('/') if _.isString(action_names)
            create = (action) ->
                action.create_action_path(action_names, $scope, $element).then (act) -> act.invoke($parse($attrs.invoke)($scope)) if $attrs.invoke?

            sc = $scope
            if sc.action
                sc = sc.$parent until sc.action instanceof E2Actions.action
                create(sc.action)
            else
                bootstrap_action_off = $scope.$on "bootstrap_action", (evt, action) ->
                    bootstrap_action_off()
                    create(action)
        else
            $http.get("api/meta").then (mresponse) -> $scope.$broadcast "bootstrap_action",
                $scope.action = new E2Actions.root(mresponse.data, $scope, null, $element, action_resource: 'api')

.factory 'E2Actions', (E2, $http, $timeout, $injector, $compile, $templateCache, $q, localStorageService, $rootScope, $location, angularLoad, $websocket, MetaCache, $stateRegistry, $urlRouter) ->
    globals = E2.globals
    action: class Action
        constructor: (response, scope, parent, element, action_info) ->
            @find_action_info = (name, raise = true) ->
                act = response.actions[name]
                throw "Undefined action '#{name}' for action #{@parent()?.action_info().action_resource}/#{@action_info().name}" if raise && !act
                act

            _.each response.actions, (act, nm) -> act.name = nm
            @meta = response.meta
            (@scope = -> scope) if scope
            @element = -> element
            @action_info = -> action_info
            @parent = -> parent

            if @meta.panel
                @default_action_name = _(response.actions).find((o) -> o.default)?.name

                scope = scope.$new(true)
                scope.$on "$destroy", (e) => @destroy(e)
                scope.action = @

                act = parent
                act = act.parent() while act && !act.meta.panel
                unless act # no modal for top level panels
                    @meta.panel.modal_action = false
                    @meta.panel.footer = true unless @meta.panel.footer == false


            if scope && @meta.invokable != false
                scope.$on action_info.action_resource, (e, args) => @invoke(args)

            @websocket_connect() if @meta.websocket
            @initialize()

        broadcast: (sub_action, args) ->
            @scope().$broadcast(@action_info().action_resource + '/' + sub_action, args)

        initialize: ->
            @process_static_meta()
            console.info "CREATE #{@action_info().action_resource}"

        process_static_meta: ->
            if @meta.menus
                _.each @meta.menus, (menu, name) => E2.process_menu @, name
        process_meta: ->

        handle_error: (err, action_info, element, create) ->
            if err.status == 401
                if action_info.access
                    $rootScope.$broadcast "relogin", element?, create
                else
                    tle = "#{err.status}: #{err.data.message}"
                    msg = err.data.cause || err.data.message
                    if msg.length > 500
                        @globals().modal().error(tle, msg)
                    else
                        @globals().toastr().error(tle, msg, extendedTimeOut: 5000, closeButton: true)

            $q.reject(err)

        save_state: () ->
            _.each @meta.state, (s) => localStorageService.set("#{@globals().application}/#{@action_info().action_resource}/#{s}", @[s])
        load_state: () ->
            _.each @meta.state, (s) => _.merge(@[s], localStorageService.get("#{@globals().application}/#{@action_info().action_resource}/#{s}"))

        destroy: (e) ->
            console.log "DESTROY #{@action_info().action_resource}"

        create_action: (name, sc, el) ->
            info = @find_action_info(name)
            info.action_resource = "#{@action_info().action_resource}/#{info.name}"
            get_meta = if !info.terminal || info.meta
                $http.get("#{info.action_resource}/meta", cache: MetaCache).then (response) =>
                    if info.recheck_access
                        $http.get("#{info.action_resource}/meta", params: (access: true, parent_id: @current_id())).then (aresponse) ->
                            response.data.actions[k].access = v for k, v of aresponse.data
                            response
                    else response # $q.when ^
            else $q.when(data: (meta: {}, actions: []))
            E2A = $injector.get("E2Actions")
            get_meta.then (mresponse) => new (E2A[info.action_type] ? E2A.default_action)(mresponse.data, sc, @, el, info)
            ,
            (err) => @handle_error(err, info, el)

        invoke_action: (name, args) ->
            @create_action(name, @scope()).then (act) -> act.invoke(args)

        create_action_path: (action_names, sc, elem) ->
            last_name = action_names.pop()
            _.reduce(action_names, ((pr, nm) -> pr.then (act) -> act.create_action(nm)), $q.when(@)).then (act) -> # self = @
                act.create_action(last_name, sc, elem).then (act) -> sc.action = act

        globals: -> globals
        _ : -> _
        current: -> @globals().current_action
        action_pending: -> globals.action_pending == @
        pre_invoke: ->
        post_invoke: ->

        invoke: (params) ->
            @globals().current_action = @
            params ?= {}
            @globals().action_pending = if @meta.panel then @ else @parent()
            @pre_invoke(params)
            if @meta.arguments # _.merge(params, @meta.arguments)
                _.each @meta.arguments, (v, k) =>
                    if _.endsWith(k, '!') then params[k.slice(0, -1)] = @scope().$eval(v) else params[k] = v


            info = @action_info()
            get_invoke = if @meta.invokable == false then $q.when(data: (response: {})) else
                params.initial = true if @meta.panel && !@action_invoked && info.method == 'get'
                $http[info.method](info.action_resource, if info.method == 'post' then params else (params: params))

            @execute_commands('pre_execute')
            get_invoke.then (response) =>
                @arguments = _.keys(response.data)
                E2.merge_meta(@, response.data)
                @process_meta()

                promise = if @meta.panel # persistent action
                    if !@action_invoked
                        @action_invoked = true
                        @panel_render()
                else
                    prnt = @parent()
                    throw "Attempted parent merge for root action: #{info.name}" unless prnt
                    E2.merge_meta(prnt, response.data)

                @post_invoke(params)
                @execute_commands('execute')
                if @meta.repeat
                    @scope().$on "$destroy", => @destroyed = true
                    $timeout (=> @invoke(params)), @meta.repeat unless @destroyed
                    delete @meta.repeat

                @globals().action_pending = false
                @globals().current_action = null
                promise
            ,
            (err) =>
                @globals().action_pending = false
                @globals().current_action = null
                @handle_error(err, info, @element())

        panel_render: ->
            if @meta.panel.modal_action
                if @element()
                    E2.fetch_panel(@meta.panel, true).then (template) =>
                        @panel_show?()
                        compiled = $compile(template)(@scope())
                        @element().empty().append(compiled.contents())
                        @panel_shown?()

                else
                    @globals().modal().show(@).then => @
            else
                @panel_scope?().$destroy()
                act = @
                act = act.parent() until act.element()
                element = act.element() # @element()
                is_modal = @globals().modal().is_modal() && !@element()
                E2.fetch_panel(@meta.panel, is_modal).then (template) =>
                    @panel_show?()
                    # @panel_scope().$destroy()
                    # @panel_scope = -> @scope().$new(false)
                    # @scope().$broadcast "$destroy"
                    @panel_scope = -> @scope().$new()
                    compiled = $compile(template)(@panel_scope())
                    if is_modal
                        element.empty().append(compiled.contents())
                    else
                        # element.empty().$destroy()
                        element.empty().append(compiled)
                    @panel_shown?()

        # panel_refresh: ->

        panel_hidden: ->
            @scope().$destroy()

        panel_close: ->
            if @meta.panel.modal_action
                @modal_hide()
            else if @parent().parent()
                # @parent().panel_refresh()
                @panel_hide?()
                @panel_hidden()
                @scope().$destroy()
                @parent().action_invoked = false
                @parent().invoke()

        panel_menu_cancel: ->
            @panel_close()

        panel_menu_close: ->
            @panel_close()

        websocket_connect: ->
            l = $location
            ws_meta = @meta.websocket
            ws = $websocket "ws#{l.protocol().slice(4, 5)}://#{l.host()}:#{l.port()}#{'/'}#{@action_info().action_resource}", undefined, ws_meta.options
            _.each @globals().ws_methods, (method) =>
                ws_method_impl = @["ws_#{method}"]
                ws["on#{_.capitalize(method)}"] (evt) =>
                    if method == 'message'
                        msg = JSON.parse(evt.data)
                        if msg.error then @globals().modal().error("WebSocket [#{evt.origin}] - #{msg.error.method}", msg.error.exception) else
                            E2.merge_meta(@, msg)
                            @process_meta()
                    else msg = evt
                    ws_method_impl.bind(@)(msg, ws, evt) if ws_method_impl
                    @execute_commands('execute')

            @web_socket = -> ws
            @scope().$on "$destroy", -> ws.close()

        execute_commands: (execute) ->
            if @meta[execute]
                scope = @scope()
                _.reduce(@meta[execute], ((pr, cmd) -> pr.then -> scope.$eval(cmd)), $q.when())
                @meta[execute].splice(0, @meta[execute].length)
                delete @meta[execute]

        console_log: (o) ->
            console.log o

    root: class RootAction extends Action
        initialize: ->
            super()
            _.merge(globals, @meta)
            @meta  = {}

        invoke: (args) ->
            console.warn "Root action invoked"

    default_action: class DefaultAction extends Action
        initialize: ->
            super()
            # console.log "DEFAULT ACTION: #{@action_info().action_resource}"

    inspect: class InspectAction extends Action
        initialize: ->
            super()
            @tree = actions: [name: 'api', number: 0, access: true]
            @invoke_action('models')
            @invoke_action('environment')
            @local_storage = localStorageService

        open: (stack, node, collapsed, expand) ->
            tree = @tree
            path = []
            _.each stack, (index) -> # fold ?
                tree = tree.actions[index]
                path.push tree.name

            # if !expand
            @number = tree.number
            if _.size(stack) > 1
                $http.get("#{_.dropRight(path).join('/')}/meta").then (response) => @action_json = _.toArray(response.data.actions)[_.last(stack)]
            else
                @action_json = {}

            # if expand && collapsed
            $http.get("#{path.join('/')}/meta").then (response) =>
                get_meta = if tree.recheck_access
                    $http.get("#{path.join('/')}/meta", params: (access: true)).then (aresponse) ->
                        response.data.actions[k].access = v for k, v of aresponse.data
                        response
                else $q.when(response)

                get_meta.then (response) =>
                    _.each response.data.actions, (act, nm) -> act.name = nm
                    tree.actions ?= _.toArray(response.data.actions)
                    @meta_json = response.data.meta
                    if @meta_json.state
                        @action_state = {}
                        _.each @meta_json.state, (s) => @action_state[s] = localStorageService.get("#{@globals().application}/#{path.join('/')}/#{s}")
                        @action_state
            ,
            (err) =>
                delete @meta_json
                @handle_error(err, access: false)

        has_assoc: (model) ->
            _.size(model.assoc) > 0

        ws_message: (msg, ws, evt) ->
            @event = evt

    menu: class MenuAction extends Action
        process_static_meta: ->

        initialize: ->
            super()
            globals.load_routes = $stateRegistry.load_routes = (init) =>
                @invoke().then =>
                    menu = @meta.menus.menu
                    _.each $stateRegistry.get(), (s) -> $stateRegistry.deregister(s.name) unless _.isEmpty(s.name)
                    otherwise = menu.properties.default ? menu.entries[0].name
                    $urlRouter.otherwise(otherwise)
                    @register(menu.entries)
                    @scope().routes = menu.entries
                    out = $compile(@traverse(menu.entries))(@scope())
                    @element().replaceWith(out)
                    @element = -> out
                    loc = $location.path().slice(1)
                    @globals().state().go(if init && !_.isEmpty($location.path()) && $stateRegistry.get(loc)? then loc else otherwise)

            $stateRegistry.load_routes(true)

        register: (routes) ->
            _.each routes, (route) =>
                unless route.divider
                    if route.menu then @register(route.menu.entries) else
                        route.href = route.name
                        if route.bootstrap?
                            action = if route.bootstrap == true then '' else route.bootstrap + '/'
                            $templateCache.put(route.name + '_route_template!', "<div e2-action='' action=\"'#{action}#{route.name}'\" invoke='true'></div>")

                        $stateRegistry.register
                            name: route.name
                            templateUrl: if route.bootstrap? then route.name + '_route_template!' else route.name
                            url: '/' + route.name
                            # reloadOnSearch: true

        traverse: (routes) ->
            menu_tmpl = _.template("<li {{show}} {{hide}} ui-sref-active='active'><a {{href}}>{{icon}} {{loc}}</a></li>")
            menu_sub_tmpl = _.template("<li {{show}} {{hide}} e2-dropdown='{{dropdown}}' nav='true' data-animation='{{animation}}'><a href='javascript://'>{{icon}} {{loc}}<span class='caret'></span></a></li>")
            animation = @meta.menus.menu.properties.animation
            out = routes.map (route, i) ->
                if route.render == false
                    ''
                else if route.menu
                    menu_sub_tmpl
                        dropdown: "routes[#{i}].menu.entries"
                        animation: animation
                        loc: route.menu.loc
                        show: route.show && "ng-show=\"#{route.show}\"" || ''
                        hide: route.hide && "ng-hide=\"#{route.hide}\"" || ''
                        icon: route.menu.icon && E2.icon(route.menu.icon) || ""
                else
                    menu_tmpl
                        href: "ui-sref='#{route.name}'"
                        loc: route.loc
                        show: route.show && "ng-show=\"#{route.show}\"" || ''
                        hide: route.hide && "ng-hide=\"#{route.hide}\"" || ''
                        icon: route.icon && E2.icon(route.icon) || ''
            out = out.join('')
            if _.size(out) == 0 then "<div></div>" else out

    list: class ListAction extends Action
        initialize: ->
            super()
            @query = page: 0, asc: true, search: {} #, search_tab: 0
            @ui_state = {}
            @load_state()

            delete @query.order unless @meta.fields[@query.order]?.sort # _.includes(@meta.field_list, @query.order)
            _.each @query.search, ((sv, sn) => delete @query.search[sn] unless _.includes(@meta.search_field_list, sn))

        destroy: ->
            @save_state()
            super()

        process_meta: ->
            super()
            meta = @meta
            meta.field_list = meta.field_list.filter((f) => !meta.fields[f].hidden) if meta.field_list

        # confirm_create, view, confirm_modify, confirm_delete, assocs - implicit

        render_table: ->
            @scope().$broadcast 'render_table'

        menu_search_toggle: ->
            @ui_state.search_active = !@ui_state.search_active
            @save_state() unless @ui_state.search_active

        menu_refresh: ->
            @invoke(refresh: true)

        menu_default_order: ->
            delete @query.order
            @invoke()

        menu_select_toggle: ->
            if @selection then delete @selection else @selection = {}
            @render_table()


        menu_show_meta: ->
            @globals().modal().show
                the_meta: @meta
                meta: panel: (panel_template: "close_m", template_string: "<pre>{{action.the_meta | yaml}}</pre>", title: "Meta", class: "modal-huge", backdrop: true, footer: true)

        # show_assoc: (index, assoc) ->
        #     # parent_id = E2.id_for(@entries[index], @meta)
        #     # @create_action(assoc, @scope(), null, parent_id).then (action) =>
        #     #     action.query.parent_id = parent_id # E2.id_for(@entries[index], @meta)
        #     #     action.invoke()
        #     @current_id = E2.id_for(@entries[index], @meta)
        #     @invoke_action(assoc)

        current_entry: ->
            @entries[@current_index]

        current_id: ->
            E2.id_for(@current_entry(), @meta)

        list_cell: (e, f) ->
            E2.render_field(e, f, @meta, "<br>")

        invoke: (args = {}) ->
            @save_state()
            query = _.cloneDeep(@query)
            delete query.search if _.isEmpty(E2.compact(query.search))
            _.merge(query, args)
            super(query).then =>
                @ui = _.pick @query, ['order', 'asc', 'page']
                @ui.pagination_active = @ui.page != 0 || @entries.length >= @meta.config.per_page
                @render_table()

        load_new: ->
            @query.page = 0
            @invoke()

        order: (col) ->
            @query.asc = if @query.order == col then !@query.asc else true
            @query.order = col
            @load_new()

        prev_active: -> !@action_pending() && @query.page > 0
        prev: ->
            if @prev_active()
                @query.page = Math.max(0, @query.page - @meta.config.per_page)
                @invoke()

        next_active: -> !@action_pending() && @entries.length == @meta.config.per_page
        next: ->
            if @next_active()
                @query.page += @meta.config.per_page # min & count
                @invoke()

        page_info: ->
            page = @ui.page / @meta.config.per_page + 1
            @meta.loc.page + ": " + if @count then "#{page} / #{Math.ceil(@count / @meta.config.per_page)} (#{@count})" else page || ''

        search_reset: ->
            E2.clean(@query.search)
            @scope().$broadcast "search_reset"
            @load_new()

        search_field_change: (f) ->
            info = @meta.fields[f]

            @scope().$eval(info.onchange.action) if info.onchange

            if remote_onchange = info.remote_onchange
                params = value: @query.search[f]
                params.record = @query.search if remote_onchange.record
                @invoke_action(remote_onchange.action, params).then =>
                    @load_new() if info.search_live
            else
                @load_new() if info.search_live

        selected_class: (index) ->
            (entry = @entries[index]) && @selection && @selection[E2.id_for(entry, @meta)] && 'info'

        select: (index, ev) ->
            if ev.target.nodeName == "TD"
                if @selection
                    rec = @entries[index]
                    id = E2.id_for(rec, @meta)
                    if @selection[id] then delete @selection[id] else @selection[id] = rec

        selected_size: ->
            _.size(@selection)

        selected_info: ->
            @meta.loc.selected + ": " + @selected_size()

        entry_dropped: (moved_to, render = true) ->
            from = @entries[@moved_from]
            @entries.splice(@moved_from, 1)
            @entries.splice((if moved_to > @moved_from then moved_to - 1 else moved_to), 0, from)
            delete @moved_from
            @render_table() if render
            true

        entry_moved: (index) ->
            @moved_from = index

        list_parent_action: ->
            parent = @parent()
            parent = parent.parent() until parent instanceof ListAction
            parent

    bulk_delete: class BulkDeleteAction extends Action
        invoke: ->
            super(ids: [_.keys(@parent().parent().selection)]).then =>
                @parent().parent().selection = {}

    view: class ViewAction extends Action
        view_cell: (e, f) ->
            E2.render_field(e, f, @meta, "<br>")

    form_base_action: class FormBaseAction extends Action
        initialize: ->
            super()
            if @meta.tab_list
                @scope().$watch "action.activeTab", (tab) => if tab? # && tab >= 0
                    @panel_shown()

            @["panel_menu_#{@default_action_name}"] = -> @panel_menu_default_action()

        post_invoke: (args) ->
            super()
            _.each @meta.fields, (info, name) =>
                if @record[name] is undefined
                    @record[name] = null
                else if _.isString(@record[name]) && !info.dont_strip
                    @record[name] = @record[name].trim()

                if info.onchange || info.remote_onchange
                    onchange = => @scope().$eval(info.onchange.action)
                    remote_onchange = =>
                        params = value: @record[name]
                        params.record = @record if info.remote_onchange.record
                        @invoke_action(info.remote_onchange.action, params)

                    @scope().$watch (=> @record[name]), (n, o) => if n != o
                        onchange() if info.onchange
                        remote_onchange() if info.remote_onchange

                    onchange() if info.onchange?.trigger_on_start
                    remote_onchange() if info.remote_onchange?.trigger_on_start

        panel_menu_default_action: ->
            params = record: @record
            params.parent_id ?= @parent().query?.parent_id # and StarToManyList ?
            @invoke_action(@default_action_name, params).then =>
                dfd = $q.defer()
                if @errors
                    if @meta.tab_list
                        [i, first, curr] = [0, null, false]
                        for tab_name in @meta.tab_list
                            tab = @meta.tabs[tab_name]
                            if _(tab.field_list).find((f) => @errors[f])
                                first = i if not first?
                                act = true if @activeTab == i
                            i++
                        @activeTab = first unless act

                        if @activeTab?
                            field = _(@meta.tabs[@meta.tab_list[@activeTab]].field_list).find((f) => @errors[f])
                            # console.log field undefined ?
                        else
                            @activeTab = 0
                            @alert = @errors
                    else
                        field = _(@meta.field_list).find((f) => @errors[f])
                        @alert = @errors if (!field || !@meta.fields[field] || @meta.fields[field].hidden) # ?
                    $timeout => @scope().$broadcast("focus_field", field)
                    #e.scope.$eval(meta.execute) if meta.execute # ?
                    dfd.resolve()
                else
                    dfd.resolve(@record) # $q.when(true) ?
                dfd.promise

        panel_shown: ->
            field = if @meta.tab_list
                tab = @meta.tabs[@meta.tab_list[@activeTab]]
                if @errors
                    _(tab.field_list).find((f) => @errors[f]) || _(tab.field_list).find((f) => !@meta.fields[f].hidden)
                else
                    tab ?= @meta.tabs[@meta.tab_list[0]]
                    _(tab.field_list).find((f) => !@meta.fields[f].hidden && !@meta.fields[f].disabled)
            else
                _(@meta.field_list).find((f) => !@meta.fields[f].hidden && !@meta.fields[f].disabled)
            $timeout (=> @scope().$broadcast("focus_field", field)), 300 # hack, on shown ?

    infra: class InfraAction extends Action
        initialize: ->
            super()
            @scope().$on "relogin", (evt, reload_routes, create) =>
                if @user
                    @invoke_action('login_form').then (act) =>
                        act.record = name: @user.name
                        act.meta.fields.name.disabled = true
                        act.dont_reload_routes = !reload_routes # true
                else
                    @invoke().then => @set_access(true, true, @user)

            @scope().$on "set_access", (evt, login, load_routes, user) => @set_access(login, load_routes, user)

        set_access: (login, load_routes, user) ->
            if user || !login
                @user = user
                @find_action_info('logout_form').access = login
                @find_action_info('inspect_modal').access = login
                @find_action_info('login_form').access = !login
                $stateRegistry.load_routes() if load_routes

    login_form: class LoginFormAction extends FormBaseAction
        panel_menu_default_action: ->
            super().then =>
                $rootScope.$broadcast "set_access", true, !@dont_reload_routes, @user

    logout_form: class LogoutForm extends Action
        panel_menu_logout: ->
            @invoke_action('logout').then =>
                $rootScope.$broadcast "set_access", false, true, null
                @panel_close()
                MetaCache.removeAll()

    form: class FormAction extends FormBaseAction

    create: class CreateAction extends FormAction
        invoke: (args) ->
            if parent_id = @parent().query.parent_id
                args ?= {}
                args.parent_id = parent_id
            super(args)

    modify: class ModifyAction extends FormAction
        # invoke: (args) ->
        #     super(args).then =>
        #         _.each @meta.primary_fields, (f) => @meta.fields[f].disabled = true

    confirm: class ConfirmAction extends Action
        panel_menu_approve: ->
            @initial_arguments ?= @arguments
            @invoke_action(@default_action_name, _.pick(@, @initial_arguments))

    decode_action: class DecodeAction extends Action
        initialize: ->
            super()
            @decode_field = @scope().f
            @dinfo = @parentp().meta.fields[@decode_field]
            throw "Primary and foreign key list lengths dont match: [#{@meta.primary_fields}] and [#{@dinfo.fields}]" unless @meta.primary_fields.length == @dinfo.fields.length
            @scope().$on "search_reset", => @clean()

        if_fk_values: (f) ->
            fk_values = @dinfo.fields.map((f) => @record()[f])
            f(fk_values) if _(fk_values).every((f) -> f?) # null_value

        record: ->
            @parentp().query?.search || @parentp().record

        clear_record: ->
            _.each @dinfo.fields, (fk) => @record()[fk] = null # null_value

        reset: ->
            @clean()
            @parentp().search_field_change?(@decode_field)

        decode_description: (entry) ->
            @meta.decode_fields.map((f) => E2.render_field(entry, f, @meta, ', ')).join(@meta.separator)

        parentp: ->
            @parent().parent()

    decode_list: class DecodeListAction extends DecodeAction
        initialize: ->
            super()
            @multiple = @dinfo.render.multiple
            @clear_selected()
            @if_fk_values (fk_values) =>
                @selected = if @multiple then E2.transpose(fk_values).map((e) -> E2.join_keys(e)) else E2.join_keys(fk_values)
            @invoke()

        clear_selected: -> @selected = if @multiple then [] else null # no need to null complex keys

        post_invoke: (args) ->
            super()
            @values = @entries.map (e) => id: E2.id_for(e, @meta), value: @decode_description(e)
            delete @entries

        change: ->
            record = @record()
            if @multiple
                if @selected.length > 0
                    _.each @dinfo.fields, (fk) -> record[fk] = []
                    _.each @selected, (sel) =>
                        _(@dinfo.fields).zip(E2.split_keys(sel)).each(([fk, k]) => record[fk].push E2.parse_entry(k, @parentp().meta.fields[fk])).value
                else @clear_record()
            else
                if @selected
                    _(@dinfo.fields).zip(E2.split_keys(@selected)).each(([fk, k]) => record[fk] = E2.parse_entry(k, @parentp().meta.fields[fk])).value
                else @clear_record()

            @parentp().search_field_change?(@decode_field)

        clean: ->
            @clear_selected()
            @clear_record()

    decode_entry: class DecodeEntryAction extends DecodeAction
        initialize: ->
            super()
            @multiple = @dinfo.render.multiple
            @if_fk_values (fk_values) =>
                @invoke_decode (if @multiple then E2.transpose(fk_values) else [fk_values])

            @scope().$on "picked", (ev, sel, sel_meta) =>
                ev.stopPropagation()
                record = @record()
                if @multiple
                    _.each @dinfo.fields, (fk) => record[fk] = []
                    _.each sel, (rec, ids) =>
                        _(@dinfo.fields).zip(E2.split_keys(ids)).each(([k, v]) => record[k].push E2.parse_entry(v, @parentp().meta.fields[k])).value
                    @invoke_decode _.values(sel)
                    delete @decode if _.isEmpty(sel)
                else
                    [ids, rec] = _(sel).toPairs().head()
                    _(@dinfo.fields).zip(E2.split_keys(ids)).each(([k, v]) => record[k] = E2.parse_entry(v, @parentp().meta.fields[k])).value
                    @invoke_decode [rec]
                @parentp().search_field_change?(@decode_field)

        invoke_decode: (recs, f) ->
            if @multiple && _.size(recs) > @meta.show_max_selected
                @decode = "#{_.size(recs)} #{@meta.loc.decode_selected}"
            else
                decode_descriptions = (recs) => @decode = recs.map((fields) => @decode_description(fields)).join(' | ')
                recs = recs.map (r) => if _.isArray(r) then E2.from_id(r, @meta) else r
                if _(recs).every((r) => _(@meta.field_list).every((f) -> r[f]?)) && !@meta.dynamic_meta then decode_descriptions(recs) else
                    @invoke(ids: [recs.map((r) => @meta.primary_fields.map (k) -> r[k])]).then => decode_descriptions(@entries)

        open: ->
            fk_values = @dinfo.fields.map((f) => @record()[f]).filter((f) -> f?)
            @create_action('list', @scope()).then (action) =>
                if @multiple
                    action.selection = E2.transpose(fk_values).reduce(((rec, keys) => rec[E2.join_keys(keys)] = E2.from_id(keys, @meta); rec), {})
                else
                    action.selection[E2.join_keys(fk_values)] = E2.from_id(fk_values, @meta) if fk_values.length > 0
                action.invoke()

        clean: ->
            delete @decode
            @clear_record()

    typeahead: class TypeAheadAction extends DecodeAction
        initialize: ->
            super()
            @scope().$on "$typeahead.select", (e, v, index) =>
                e.stopPropagation()
                _(@dinfo.fields).zip(E2.split_keys(@values[index].id)).each(([fk, k]) => @record()[fk] = E2.parse_entry(k, @parentp().meta.fields[fk])).value
                @parentp().scope().$digest()
                @parentp().search_field_change?(@decode_field)

            @scope().$watch "action.decode", (e) => @reset() if e == null

            @if_fk_values (fk_values) =>
                @invoke(id: E2.join_keys(fk_values)).then =>
                    if @entry
                        @decode = id: E2.id_for(@entry, @meta), value: @decode_description(@entry)

            @decode = '' unless @decode?
            # @dinfo.render.min_length == 0

        load: (value) ->
            if _.isString(value)
                @invoke(query: value).then => if @entries # ?
                    @values = @entries.map (e) => id: E2.id_for(e, @meta), value: @decode_description(e)
                    delete @entries
                    @values

        clean: ->
            @decode = ''
            @clear_record()

    many_to_one_list: class ManyToOneListAction extends ListAction
        initialize: ->
            super()
            @selection = {}

        select: (index, ev) ->
            if ev.target.nodeName == "TD"
                @selection = {} unless @parent().multiple
                super(index, ev)
                unless @parent().multiple
                    @scope().$emit "picked", @selection, @meta
                    @panel_close()

        panel_menu_choose: (e) ->
            # if _.size(@selection) > 0
            @scope().$emit "picked", @selection, @meta
            @panel_close()

    star_to_many_list: class StarToManyList extends ListAction
        initialize: ->
            super()
            @query.parent_id = @list_parent_action().current_id()

        # link_list: implicit
        item_menu_confirm_unlink: (args) ->
            args.parent_id = @query.parent_id
            @item_menu_confirm_unlink_super(args)

    star_to_many_bulk_unlink: class StarToManyBulkUnlinkAction extends Action
        invoke: ->
            parent = @parent().parent()
            super(ids: [_.keys(parent.selection)], parent_id: parent.query.parent_id).then =>
                parent.selection = {}

    star_to_many_link_list: class StarToManyLinkList extends ListAction
        initialize: ->
            super()
            @query.negate = true
            @query.parent_id = @parent().query.parent_id
            @selection = {}

        panel_menu_link: ->
            selection = _.keys(@selection)
            if selection.length > 0
                @invoke_action('link', parent_id: @query.parent_id, ids: selection)

    star_to_many_field: class StarToManyField extends ListAction
        initialize: ->
            super()
            @query.parent_id = E2.id_for(@parent().record, @parent().meta)
            @changes = @parent().record[@scope().$parent.f] ? (link: [], unlink: [], create: [], modify: [], delete: [])
            @invoke()

        invoke: ->
            @query.changes = @parent().record[@scope().$parent.f] = @changes
            super()

        entry_dropped: (moved_to) ->
            pos_field = @meta.draggable.position_field
            positions = @entries.map (e) -> e[pos_field]
            super(moved_to, false)
            _.each positions, (p, i) =>
                if @entries[i][pos_field] != p
                    if entry = @current_entry_is('create', @entries[i]) ? @current_entry_is('modify', @entries[i])
                        entry[pos_field] = p
                    else
                        @changes.modify.push(@entries[i])
                    @entries[i][pos_field] = p

            @render_table() # @invoke()
            true

        current_entry_is: (mode, entry = @current_entry()) ->
            key = E2.id_for(entry, @meta)
            _.find(@changes[mode], (e) => E2.id_for(e, @meta) == key)

    star_to_many_field_view: class StarToManyFieldView extends ViewAction
        invoke: (args) ->
            if entry = @parent().current_entry_is('create') ? @parent().current_entry_is('modify')
                @meta.invokable = false
                @record = entry
            super(args)

    star_to_many_field_modify: class StarToManyFieldModifyAction extends ModifyAction
        invoke: (args) ->
            if entry = @parent().current_entry_is('create') ? @parent().current_entry_is('modify')
                @meta.invokable = false
                @record = entry
            super(args)

    star_to_many_field_approve: class StarToManyFieldApprove extends Action
        post_invoke: (args) ->
            super(args)
            unless @errors
                pparent = @parent().parent()
                if @parent() instanceof StarToManyFieldModifyAction
                    if entry = pparent.current_entry_is('create') ? pparent.current_entry_is('modify')
                        _.assign(entry, @parent().record)
                    else
                        pparent.changes.modify.push @parent().record
                else # CreateAction
                    _(@parent().meta.primary_fields).each (k) => @parent().record[k] = E2.uuid()
                    if draggable = pparent.meta.draggable
                        max = _.maxBy(pparent.entries, (e) -> e.position)
                        @parent().record[draggable.position_field] = if max then max[draggable.position_field] + 1 else 1
                    pparent.changes.create.push @parent().record

    star_to_many_field_delete: class StarToManyFieldDelete extends Action
        invoke: (args) ->
            pparent = @parent().parent()
            if entry = pparent.current_entry_is('create')
                _.remove(pparent.changes.create, entry)
            else if entry = pparent.current_entry_is('modify')
                _.remove(pparent.changes.modify, entry)
                pparent.changes.delete.push args.id
            else
                pparent.changes.delete.push args.id
            @meta.invokable = false
            super(args)

    star_to_many_field_link_list: class StarToManyFieldLinkList extends ListAction
        initialize: ->
            super()
            @query.negate = true
            @query.parent_id = @parent().query.parent_id
            @selection = {}

        invoke: ->
            @query.changes = @parent().changes
            super()

        panel_menu_link: ->
            if @selected_size() > 0
                _.each @selection, (v, k) =>
                    id = k
                    if _.includes(@parent().changes.unlink, id) then _.pull(@parent().changes.unlink, id) else @parent().changes.link.push id
                @parent().invoke()
                @panel_close()

    star_to_many_field_unlink: class StarToManyFieldUnlink extends Action
        invoke: (args) ->
            id = args.id
            pparent = @parent().parent()
            if _.includes(pparent.changes.link, id) then _.pull(pparent.changes.link, id) else pparent.changes.unlink.push id
            @meta.invokable = false
            super(args)

    file_store: class FileStoreAction extends Action
        initialize: ->
            super()
            @progress = 0
            id = E2.id_for(@parent().record, @parent().meta)
            files = @parent().record[@scope().f]
            @invoke(owner: id).then =>
                @parent().record[@scope().f] = if files? then files else @files
                delete @files

        select: (files) ->
            _.each files, (file) =>
                upload = $injector.get('Upload').upload url: "#{@action_info().action_resource}/upload", file: file
                upload.progress (e) =>
                    @globals().action_pending = false
                    @progress = parseInt(100.0 * e.loaded / e.total)
                upload.success (data, status, headers, config) =>
                    @parent().record[@scope().f].push mime: file.type, name: file.name, rackname: data.rackname, id: data.id, new: true
                    @message = "Wysłano, #{file.name}"
                    @globals().action_pending = false

        delete_file: (file) ->
            @scope().$broadcast 'confirm_delete',
                confirm: =>
                    if file.new then _.pull(@parent().record[@scope().f], file) else file.deleted = true
                    @scope().$broadcast 'confirm_delete_close'

        show_file: (file) ->
            @file = file
            @scope().$broadcast 'show_file', file: file

    blob_store: class BlobStore extends Action
        initialize: ->
            super()
            @record_id = E2.id_for(@parent().record, @parent().meta)
            @progress = 0
            if @record_id.length > 0
                @invoke(owner: @record_id) # .then => @sync_record()
            else
                # @file = {}
                # @sync_record()

        sync_record: ->
            @parent().record[@scope().f] = @file

        select: (files) ->
            _.each files, (file) =>
                upload = $injector.get('Upload').upload url: "#{@action_info().action_resource}/upload", file: file
                upload.progress (e) =>
                    @progress = parseInt(100.0 * e.loaded / e.total)
                upload.success (data, status, headers, config) =>
                    @file = mime: file.type, name: file.name, rackname: data.rackname, id: data.id
                    @message = "Wysłano, #{file.name}"
                    @sync_record()
