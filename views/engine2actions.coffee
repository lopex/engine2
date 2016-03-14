angular.module('Engine2')
.directive 'e2Action', (E2Actions) ->
    scope: true
    controller: ($scope, $attrs, $parse, $element, $http) ->
        if action_attr = $attrs.action
            action_names = $parse(action_attr)($scope)
            throw "Invalid action path: '#{action_attr}'" unless action_names
            action_names = action_names.split('/') if _.isString(action_names)
            create = (action) ->
                action.create_action_path(action_names, $scope, $element).then (act) -> act.invoke() if $attrs.invoke

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
                $scope.action = new E2Actions.default_action(mresponse.data, $scope, null, $element, action_resource: 'api')

.factory 'E2Actions', (E2, $http, $timeout, $e2Modal, $injector, $compile, $templateCache, $q, localStorageService, $route, $window, $rootScope, $location) ->
    action: class Action
        constructor: (response, scope, parent, element, action_info) ->
            @find_action_info = (name, raise = true) ->
                act = response.actions[name]
                throw "Undefined action '#{name}' for action #{@action_info().name} (under #{parent.action_info().action_resource})" if raise && !act
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
                    if @meta.menus.panel_menu
                        _.remove(@meta.menus.panel_menu.entries, (m) -> m.name == 'cancel')

            @initialize()

        initialize: ->
            @process_static_meta()
            @process_meta()
            console.log "CREATE #{@action_info().action_resource}"

        process_static_meta: ->
            if @meta.menus
                _.each @meta.menus, (menu, name) => E2.process_menu @, name
        process_meta: ->

        handle_error: (err, action_info, element, create) ->
            if err.status == 401
                if action_info.access
                    $rootScope.$broadcast "relogin", element?, create
                else
                    $e2Modal.error("#{err.status}: #{err.data.message}", err.data.cause || err.data.message)
            $q.reject(err)

        perform_invoke: (params) ->
            info = @action_info()
            get_invoke = if info.invokable
                params.initial = true if !@action_invoked && params && info.method == 'get'
                $http[info.method](info.action_resource, if info.method == 'post' then params else (params: params))
            else $q.when(data: (response: {}))

            get_invoke.then (response) =>
                E2.merge(@meta, response.data.meta)
                @process_meta()
                _.assign(@, response.data.response)
                if @meta.response
                    E2.merge(@, @meta.response)
                    delete @meta.response
                @arguments = _.keys(response.data.response)
                unless @meta.panel # persistent action
                    prnt = @parent()
                    throw "Attempted parent merge for root action: #{info.name}" unless prnt
                    E2.merge(prnt.meta, @meta)
                    _.assign(prnt, response.data.response)

                # promise = if @meta.panel && !@action_invoked
                # $q.when(promise) # .then -> response.data
                if @meta.panel && !@action_invoked
                    @action_invoked = true
                    @panel_render()
                # else $q.when()
            ,
            (err) =>
                @parent().action_pending = false
                @handle_error(err, info, @element())

        create_action: (name, sc, el) ->
            info = @find_action_info(name)
            info.action_resource = "#{@action_info().action_resource}/#{info.name}"
            get_meta = if !info.terminal || info.meta
                $http.get("#{info.action_resource}/meta", cache: true).then (response) =>
                    if info.recheck_access
                        $http.get("#{info.action_resource}/meta", params: (access: true, parent_id: @current_id)).then (aresponse) ->
                            response.data.actions[k].access = v for k, v of aresponse.data
                            response
                    else response # $q.when ^
            else $q.when(data: (meta: {}, actions: []))
            E2A = $injector.get("E2Actions")
            get_meta.then (mresponse) => new (E2A[info.meta_type] ? E2A.default_action)(mresponse.data, sc, @, el, info)
            ,
            (err) => @handle_error(err, info, el)

        invoke_action: (name, arg) ->
            @create_action(name, @scope()).then (act) -> act.invoke(arg)

        create_action_path: (action_names, sc, elem) ->
            last_name = action_names.pop()
            _.foldl(action_names, ((pr, nm) -> pr.then (act) -> act.create_action(nm)), $q.when(@)).then (act) ->
                act.create_action(last_name, sc, elem).then (act) -> sc.action = act

        pre_invoke: ->
            @parent().action_pending = true
            # @parent().parent().action_pending = true if @parent().parent()
        post_invoke: ->
            delete @parent().action_pending # = false
            # @parent().parent().action_pending = false if @parent().parent()
        invoke: ->
            args = arguments
            @pre_invoke(args...)
            @perform_invoke(args...).then (response) =>
                @post_invoke(args...)
                @

        save_state: () ->
            _.each @meta.state, (s) => localStorageService.set("#{@action_info().action_resource}/#{s}", @[s])
        load_state: () ->
            _.each @meta.state, (s) => E2.merge(@[s], localStorageService.get("#{@action_info().action_resource}/#{s}"))

        destroy: (e) ->
            console.log "DESTROY #{@action_info().action_resource}"

        panel_render: ->
            if @meta.panel.modal_action
                if @element()
                    E2.fetch_panel(@meta.panel, true).then (template) =>
                        @panel_show?()
                        compiled = $compile(template)(@scope())
                        @element().empty().append(compiled.contents())
                        @panel_shown?()

                else
                    $e2Modal.show(@)
            else
                @panel_scope?().$destroy()
                act = @
                act = act.parent() until act.element()
                element = act.element() # @element()
                is_modal = $e2Modal.is_modal() && !@element()
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
            else
                # @parent().panel_refresh()
                @panel_hide?()
                @panel_hidden()
                @scope().$destroy()
                @parent().action_invoked = false
                @parent().invoke()

        panel_menu_cancel: ->
            @panel_close()

    default_action: class DefaultAction extends Action
        initialize: ->
            super()
            # console.log "DEFAULT ACTION: #{@action_info().action_resource}"

    inspect: class InspectAction extends Action
        initialize: ->
            super()
            @tree = actions: [name: 'api', number: 0, access: true]
            @invoke_action('models')

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
                    @action_state = if @meta_json.state then _.zipObject(@meta_json.state.map (k) -> [k, localStorageService.get("#{path}/#{k}")]) else {}
            ,
            (err) =>
                delete @meta_json
                @handle_error(err, access: false)

        has_assoc: (model) ->
            _.size(model.assoc) > 0

    menu: class MenuAction extends Action
        process_static_meta: ->

        initialize: ->
            super()
            $route.load_routes = =>
                @invoke().then =>
                    _.each _.keys($route.routes), (k) -> delete $route.routes[k]
                    menu = @meta.menus.menu
                    $route.routes[null] = reloadOnSearch: true, redirectTo: '/' + (menu.properties.default ? menu.entries[0].name)
                    @register(menu.entries)
                    $route.reload() # $location.path('')
                    @scope().routes = menu.entries
                    out = if _.size(menu.entries) == 0 then angular.element("<div></div>") else $compile(@traverse(menu.entries))(@scope())
                    @element().replaceWith(out)
                    @element = -> out
            $route.load_routes()

        register: (routes) ->
            _.each routes, (route) =>
                if route.menu then @register(route.menu.entries) else
                    name = '/' + route.name
                    route.href = '#' + route.name
                    $templateCache.put(route.name, "<div e2-action='' action=\"'#{route.bootstrap}/#{route.name}'\" invoke='true'></div>") if route.bootstrap
                    $route.routes[name] =
                        reloadOnSearch: true
                        templateUrl: route.name
                        originalPath: name
                        regexp: new RegExp("^#{name}$")
                        keys: []

                    $route.routes[name + '/'] =
                        redirectTo: name
                        originalPath: name + '/'
                        regexp: new RegExp("^#{name}/$")
                        keys: []

        traverse: (routes) ->
            menu_tmpl = _.template("<li><a href='{{href}}'>{{icon}}{{aicon}}{{loc}}</a></li>")
            menu_sub_tmpl = _.template("<li e2-drop-down='{{dropdown}}'><a href='javascript://'>{{icon}}{{aicon}}{{loc}}<span class='caret'></span></a></li>")
            out = routes.map (route, i) ->
                if route.menu
                    menu_sub_tmpl
                        icon: route.menu.icon && E2.icon(route.menu.icon) || ""
                        aicon: route.menu.aicon && E2.aicon(route.menu.aicon) || ""
                        loc: route.menu.loc
                        dropdown: "routes[#{i}].menu.entries"
                else
                    menu_tmpl
                        href: route.href
                        loc: route.loc
                        icon: route.icon && E2.icon(route.icon) || ''
                        aicon: route.aicon && E2.aicon(route.aicon) || ''
            out.join('')

    # dummy: class DummyAction extends Action

    list: class ListAction extends Action
        initialize: ->
            super()
            @query = page: 0, asc: true, search: {} #, search_tab: 0
            @ui_state = {}
            @load_state()

            delete @query.order unless _.contains(@meta.fields, @query.order)
            _.each @query.search, ((sv, sn) => delete @query.search[sn] unless _.contains(@meta.search_fields, sn))

            _.each @meta.info, (info, name) =>
                if info.remote_onchange
                    @scope().$watch (=> @query.search?[name]), (n) => if n?
                        params = value: @query.search[name]
                        params.record = @query.search if info.remote_onchange_record
                        @invoke_action(info.remote_onchange, params)

                if info.onchange
                    @scope().$watch (=> @query.search?[name]), (n) => if n?
                        @scope().$eval(info.onchange)

            # $window.addEventListener 'beforeunload', (e, v) => @save_state()

        destroy: ->
            @save_state()
            super()

        process_meta: ->
            super()
            meta = @meta
            meta.fields = meta.fields.filter((f) => !meta.info[f].hidden) if meta.fields

        # confirm_create, view, confirm_modify, confirm_delete, assocs - implicit

        menu_search_toggle: ->
            @ui_state.search_active = !@ui_state.search_active
            @save_state() unless @ui_state.search_active

        menu_refresh: ->
            @invoke()

        menu_default_order: ->
            delete @query.order
            @invoke()

        menu_select_toggle: ->
            if @selection then delete @selection else @selection = {}
            @scope().$broadcast 'render_table'

        menu_show_meta: ->
            $e2Modal.show
                the_meta: @meta
                meta: panel: (panel_template: "close_m", template_string: "<pre>{{action.the_meta | json}}</pre>", title: "Meta", class: "modal-huge")

        # show_assoc: (index, assoc) ->
        #     # parent_id = E2.id_for(@entries[index], @meta)
        #     # @create_action(assoc, @scope(), null, parent_id).then (action) =>
        #     #     action.query.parent_id = parent_id # E2.id_for(@entries[index], @meta)
        #     #     action.invoke()
        #     @current_id = E2.id_for(@entries[index], @meta)
        #     @invoke_action(assoc)

        list_cell: (e, f) ->
            E2.render_field(e, f, @meta)

        invoke: ->
            @save_state()
            query = _.cloneDeep(@query)
            delete query.search if _.isEmpty(E2.compact(query.search))
            super(query).then =>
                @ui = _.pick @query, ['order', 'asc', 'page']
                @scope().$broadcast 'render_table'

        load_new: ->
            @query.page = 0
            @invoke()

        order: (col) ->
            @query.asc = if @query.order == col then !@query.asc else true
            @query.order = col
            @load_new()

        prev_active: -> @query.page > 0
        prev: ->
            @query.page = Math.max(0, @query.page - @meta.config.per_page)
            @invoke()

        next_active: -> @entries.length == @meta.config.per_page
        next: ->
            @query.page += @meta.config.per_page # min & count
            @invoke()

        page_info: ->
            page = @ui.page / @meta.config.per_page + 1
            if @count then "#{page} / #{Math.ceil(@count / @meta.config.per_page)} (#{@count})" else page || ''

        search_reset: ->
            E2.clean(@query.search)
            @scope().$broadcast "search_reset"
            @load_new()

        search_live: (f) ->
            @load_new() if @meta.info[f].search_live

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

    bulk_delete: class BulkDeleteAction extends Action
        invoke: ->
            super(ids: [_.keys(@parent().parent().selection)]).then =>
                @parent().parent().selection = {}

    view: class ViewAction extends Action
        view_cell: (e, f) ->
            E2.render_field(e, f, @meta)

    form_base_action: class FormBaseAction extends Action
        initialize: ->
            super()
            _.each @meta.info, (info, name) =>
                if info.remote_onchange
                    @scope().$watch (=> @record?[name]), (n) => if n? #if typeof(n) != "undefined"
                        params = value: @record[name]
                        params.record = @record if info.remote_onchange_record
                        @invoke_action(info.remote_onchange, params)

                if info.onchange
                    @scope().$watch (=> @record?[name]), (n) => if n?
                        @scope().$eval(info.onchange)

            if @meta.tabs
                @scope().$watch "action.activeTab", (tab) => if tab? # && tab >= 0
                    @panel_shown()

            @["panel_menu_#{@default_action_name}"] = -> @panel_menu_default_action()
            @scope().$on "return_pressed", (e) => @panel_menu_default_action()

        post_invoke: (args) ->
            super()
            _.each @meta.info, (info, name) =>
                if _.isString(@record[name]) && !info.dont_strip
                    @record[name] = @record[name].trim()

        panel_menu_default_action: ->
            _.each @meta.info, (v, n) =>
                @record[n] = null if @record[n] is undefined

            @invoke_action(@default_action_name, record: @record).then =>
                dfd = $q.defer()
                if @errors
                    if @meta.tabs
                        [i, first, curr] = [0, null, false]
                        for tab in @meta.tabs
                            if _(tab.fields).find((f) => @errors[f])
                                first = i if not first?
                                act = true if @activeTab == i
                            i++
                        @activeTab = first unless act

                        if @activeTab?
                            field = _(@meta.tabs[@activeTab].fields).find((f) => @errors[f])
                            # console.log field undefined ?
                        else
                            @activeTab = 0
                            @alert = @errors
                    else
                        field = _(@meta.fields).find((f) => @errors[f])
                        @alert = @errors if (!field || !@meta.info[field] || @meta.info[field].hidden) # ?
                    $timeout => @scope().$broadcast("focus_field", field)
                    #e.scope.$eval(meta.execute) if meta.execute # ?
                    dfd.reject(@errors)
                else
                    @panel_close()
                    dfd.resolve(@record) # $q.when(true) ?
                dfd.promise

        panel_shown: ->
            field = if @meta.tabs
                tab = @meta.tabs[@activeTab]
                if @errors
                    _(tab.fields).find((f) => @errors[f]) || _(tab.fields).find((f) => !@meta.info[f].hidden)
                else
                    tab ?= @meta.tabs[0]
                    _(tab.fields).find((f) => !@meta.info[f].hidden && !@meta.info[f].disabled)
            else
                _(@meta.fields).find((f) => !@meta.info[f].hidden && !@meta.info[f].disabled)
            $timeout (=> @scope().$broadcast("focus_field", field)), 300 # hack, on shown ?

    infra: class InfraAction extends Action
        initialize: ->
            super()
            @scope().$on "relogin", (evt, reload_routes, create) =>
                if @user
                    @invoke_action('login_form').then (act) =>
                        act.record = name: @user.name
                        act.meta.info.name.disabled = true
                        act.dont_reload_routes = !reload_routes # true
                else
                    @invoke().then => @set_access(true, true)

        set_access: (login, load_routes) ->
            @find_action_info('logout_form').access = login
            @find_action_info('inspect_modal').access = login
            @find_action_info('login_form').access = !login
            $route.load_routes() if load_routes

    login_form: class LoginFormAction extends FormBaseAction
        panel_menu_default_action: ->
            super().then =>
                @parent().user = @user
                @parent().set_access(true, !@dont_reload_routes)

    logout_form: class LogoutForm extends Action
        panel_menu_logout: ->
            @invoke_action('logout').then =>
                @parent().user = null
                @parent().set_access(false, true)
                @panel_close()

    form: class FormAction extends FormBaseAction
        panel_menu_default_action: ->
            super().then => @parent().invoke()

    create: class CreateAction extends FormAction
        invoke: (args) ->
            if parent_id = @parent().query.parent_id
                args ?= {}
                args.parent_id = parent_id
            super(args)

    modify: class ModifyAction extends FormAction
        # invoke: (args) ->
        #     super(args).then =>
        #         _.each @meta.primary_fields, (f) => @meta.info[f].disabled = true

    on_change: class OnChangeAction extends Action
        post_invoke: ->
            super()
            @parent().scope().$eval(@meta.execute) if @meta.execute

    confirm: class ConfirmAction extends Action
        panel_menu_approve: ->
            @initial_arguments ?= @arguments
            @invoke_action(@default_action_name, _.pick(@, @initial_arguments)).then (act) =>
                unless @errors
                    @parent().invoke()
                    @panel_close()

    decode_action: class DecodeAction extends Action
        initialize: ->
            super()
            @decode_field = @scope().f
            @dinfo = @parentp().meta.info[@decode_field]
            @scope().$on "search_reset", => @clean()

        if_fk_values: (f) ->
            fk_values = @dinfo.fields.map((f) => @record()[f])
            f(fk_values) if _(fk_values).all((f) -> f?) # null_value

        record: ->
            @parentp().query?.search || @parentp().record

        clear_record: ->
            _.each @dinfo.fields, (fk) => @record()[fk] = null # null_value

        reset: ->
            @clean()
            @parentp().search_live?(@decode_field)

        decode_description: (entry) ->
            fields = @meta.decode_fields ? @meta.fields
            fields.map((f) => E2.render_field(entry, f, @meta)).join(@meta.separator)

        parentp: ->
            @parent().parent()

    decode_list: class DecodeListAction extends DecodeAction
        initialize: ->
            super()
            @multiple = @dinfo.render.multiple
            @clear_selected()
            @if_fk_values (fk_values) =>
                @selected = if @multiple then E2.transpose(fk_values).map(E2.join_keys) else E2.join_keys(fk_values)
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
                        _(@dinfo.fields).zip(E2.split_keys(sel)).each(([fk, k]) => record[fk].push E2.parse_entry(k, @parentp().meta.info[fk])).value()
                else @clear_record()
            else
                if @selected
                    _(@dinfo.fields).zip(E2.split_keys(@selected)).each(([fk, k]) => record[fk] = E2.parse_entry(k, @parentp().meta.info[fk])).value()
                else @clear_record()

            @parentp().search_live?(@decode_field)

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
                        _(@dinfo.fields).zip(E2.split_keys(ids)).each(([k, v]) => record[k].push E2.parse_entry(v, @parentp().meta.info[k])).value()
                    @invoke_decode _.values(sel)
                    delete @decode if _.isEmpty(sel)
                else
                    [ids, rec] = _(sel).pairs().head()
                    _(@dinfo.fields).zip(E2.split_keys(ids)).each(([k, v]) => record[k] = E2.parse_entry(v, @parentp().meta.info[k])).value()
                    @invoke_decode [rec]
                @parentp().search_live?(@decode_field)

        invoke_decode: (recs, f) ->
            if @multiple && _.size(recs) > @meta.show_max_selected
                @decode = "#{_.size(recs)} #{@meta.decode_selected}"
            else
                decode_descriptions = (recs) => @decode = recs.map((fields) => @decode_description(fields)).join(' | ')
                recs = recs.map (r) => if _.isArray(r) then E2.from_id(r, @meta) else r
                if _(recs).all((r) => _(@meta.fields).all((f) -> r[f]?)) then decode_descriptions(recs) else
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
            @if_fk_values (fk_values) =>
                @invoke(id: E2.join_keys(fk_values)).then =>
                    if @entry
                        @decode = id: E2.id_for(@entry, @meta), value: @decode_description(@entry)

            @scope().$on "$typeahead.select", (e, v, index) =>
                e.stopPropagation()
                _(@dinfo.fields).zip(E2.split_keys(@values[index].id)).each(([fk, k]) => @record()[fk] = E2.parse_entry(k, @parentp().meta.info[fk])).value()
                @parentp().search_live?(@decode_field)

            @scope().$watch "action.decode", (e) => if e?
                @reset() if e.length == 0

        load: (value) ->
            if value? && value.length > 0 && @key_pressed # check again after strap updates ?
                @invoke(query: value).then =>
                    if @entries # ?
                        @values = @entries.map (e) => id: E2.id_for(e, @meta), value: @decode_description(e)
                        delete @entries
                        @values

        clean: ->
            delete @decode
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
            @query.parent_id = @parent().current_id

        # link_list: implicit
        item_menu_confirm_unlink: (index) ->
            @invoke_action('confirm_unlink', id: E2.id_for(@entries[index], @meta), parent_id: @query.parent_id)

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
                @invoke_action('link', parent_id: @query.parent_id, ids: selection).then (act) =>
                    unless @errors
                        @parent().invoke()
                        @panel_close()

    star_to_many_field: class StarToManyField extends ListAction
        initialize: ->
            super()
            @query.parent_id = E2.id_for(@parent().record, @parent().meta)
            links = @parent().record[@scope().$parent.f]
            @links = links ? (linked: [], unlinked: [])
            # console.log @parent().meta.primary_fields.map((f) => @parent().record[f])
            # if E2.id_for(@parent().record, @parent().meta).all((e) -> e?)
            @invoke() if @query.parent_id.length > 0

        invoke: ->
            @query.unlinked = [@links.unlinked]
            @query.linked = [@links.linked]
            super()

        sync_record: ->
            @parent().record[@scope().$parent.f] = @links

    star_to_many_field_link_list: class StarToManyFieldLinkList extends ListAction
        initialize: ->
            super()
            @query.negate = true
            @query.parent_id = @parent().query.parent_id
            @selection = {}

        invoke: ->
            @query.unlinked = [@parent().links.unlinked]
            @query.linked = [@parent().links.linked]
            super()

        panel_menu_link: ->
            if @selected_size() > 0
                _.each @selection, (v, k) =>
                    id = k
                    if _.contains(@parent().links.unlinked, id) then _.pull(@parent().links.unlinked, id) else @parent().links.linked.push id
                @parent().invoke()
                @parent().sync_record()
                @panel_close()

    star_to_many_field_unlink: class StarToManyFieldUnlink extends Action
        invoke: (arg) ->
            id = arg.id
            pparent = @parent().parent()
            if _.contains(pparent.links.linked, id) then _.pull(pparent.links.linked, id) else pparent.links.unlinked.push id
            pparent.sync_record()

    file_store: class FileStoreAction extends Action
        initialize: ->
            super()
            @progress = 0
            id = E2.id_for(@parent().record, @parent().meta)
            if id.length > 0
                @invoke(owner: id).then => @sync_record()
            else
                @files = []
                @sync_record()

        sync_record: ->
            @parent().record[@scope().f] = @files

        select: (files) ->
            _.each files, (file) =>
                upload = $injector.get('$upload').upload url: "#{@action_info().action_resource}/upload", file: file
                upload.progress (e) =>
                    @progress = parseInt(100.0 * e.loaded / e.total)
                    # @parent().action_pending = true
                upload.success (data, status, headers, config) =>
                    @files.push mime: file.type, name: file.name, rackname: data.response.rackname, id: data.response.id
                    @message = "Wysłano, #{file.name}"
                    # @parent().action_pending = false
            @sync_record()

        delete_file: (file) ->
            @scope().$broadcast 'confirm_delete',
                confirm: =>
                    @sync_record()
                    file.deleted = true
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
                upload = $injector.get('$upload').upload url: "#{@action_info().action_resource}/upload", file: file
                upload.progress (e) =>
                    @progress = parseInt(100.0 * e.loaded / e.total)
                upload.success (data, status, headers, config) =>
                    @file = mime: file.type, name: file.name, rackname: data.response.rackname, id: data.response.id
                    @message = "Wysłano, #{file.name}"
                    @sync_record()
