'use strict'
_.templateSettings.interpolate = /{{([\s\S]+?)}}/g;

angular.module('Engine2', ['ngRoute', 'ngSanitize', 'ngAnimate', 'ngCookies', 'mgcrea.ngStrap', 'ngFileUpload', 'ui.tree', 'LocalStorageModule']) # 'draggabilly'
.config ($httpProvider, $routeProvider, $compileProvider, localStorageServiceProvider, $logProvider) ->
    loaderOn = -> angular.element(document.querySelectorAll('.loader')).eq(-1).css("visibility", 'visible')
    $httpProvider.interceptors.push 'e2HttpInterceptor'
    $httpProvider.defaults.transformRequest.push (data, headersGetter) ->
        loaderOn()
        data
    # $httpProvider.defaults.headers.common['Cache-Control'] = 'no-cache'
    # $httpProvider.defaults.cache = false;
    $httpProvider.defaults.headers.get ||= {} # if !$httpProvider.defaults.headers.get
    $httpProvider.defaults.headers.get['If-Modified-Since'] = '0'
    # localStorageServiceProvider.setStorageType('sessionStorage')
    localStorageServiceProvider.setPrefix('E2')
    $compileProvider.debugInfoEnabled(false)
    $logProvider.debugEnabled(true)
    $httpProvider.useApplyAsync(true)
    # $locationProvider.html5Mode(true);

.factory 'e2HttpInterceptor', ($q, $injector, E2Snippets) ->
    loaderOff = -> angular.element(document.querySelectorAll('.loader')).eq(-1).css("visibility", 'hidden')
    response: (response) ->
        loaderOff()
        response

    responseError: (response) ->
        loaderOff()
        if response.status != 401
            response = (status: response.status, statusText: "Connection refused", data: (message: "Connection refused")) if response.status in [-1, 0]
            if response.constructor == SyntaxError
                message = response.message
                cause = response.stack
            else
                message = response.data.message
                cause = if _.isString(response.data) then response.data else response.data.cause || response.data.message
            $injector.get('$e2Modal').error("#{E2Snippets.icon('bell')} #{response.status}: #{message}", cause)
        $q.reject(response)

.factory 'E2Snippets', ->
    icon = (name) -> "<span class='glyphicon glyphicon-#{name}'></span>"
    aicon = (name) -> "<i class='fa fa-#{name}'></i>"
    ng_class_names = ['active', 'enabled', 'disabled']
    icon: icon
    aicon: aicon
    boolean_true_value:     icon('check')
    boolean_false_value:    icon('unchecked')
    make_ng_class: (o) ->
        out = []
        _.each ng_class_names, (e) -> out.push(if e == 'enabled' then "'disabled': !(#{o[e]})" else "'#{e}': #{o[e]}") if o[e]?
        _.each(o.class, (v, k) -> out.push "#{k}: #{v}") if o.class?
        if out.length > 0 then "ng-class=\"{#{out.join(',')}}\"" else ""

.factory 'E2', ($templateCache, $http, E2Snippets, $e2Modal, $q, $injector, e2HttpInterceptor, $route, $dateFormatter, $parse) ->
    globals: {}

    compact: (o) ->
        _.each o, (v, k) =>
            if (v == null || (_.isString(v) && !v)) || (!_.isDate(v) && _.isObject(v) && @compact(v) && _.isEmpty(v))
                delete o[k]

    clean: (o) ->
        _.each o, (v, k) =>
            if _.isArray(v)
                v.length = 0 # o[k] = []
            else if _.isObject(v) && !_.isDate(v)
                @clean(v)
            else
                # delete o[k]
                o[k] = null

    merge: (dst, src) ->
        for k, v of src
            if _.isObject(v) && !_.isArray(v)
                if k.slice(-1) == '!'
                    dst[k.slice(0, -1)] = v
                else
                    dst[k] = @merge(dst[k] ? {}, v)
            else
                dst[k] = v
        dst

    transpose: (a) ->
        _.keys(a[0]).map((c) -> a.map (r) -> r[c])

    join_keys: (keys) -> keys.join(@globals.key_separator)
    split_keys: (key) -> key.split(@globals.key_separator)
    id_for: (rec, meta) -> @join_keys(meta.primary_fields.map((e) -> rec[e]))
    from_id: (id, meta) -> _.zipObject(meta.primary_fields, id) # _.zip(meta.primary_fields, id).reduce(((rec, [k, v]) -> rec[k] = v; rec), {})

    icon: E2Snippets.icon
    aicon: E2Snippets.aicon

    fetch_template: (template) ->
        $q.when($templateCache.get(template) || $http.get(template)).then (res) ->
            if angular.isObject(res)
                $templateCache.put(template, res.data)
                res.data
            else res

    fetch_panel: (panel, modal) ->
        $q.when(panel.template_string || @fetch_template(panel.template)).then (template) =>
            if panel.panel_template
                prefix = if modal then 'modals' else 'panels'
                @fetch_template("#{prefix}/#{panel.panel_template}").then (panel_template) -> panel_template.replace("modal-content-to-replace", template)
            else template

    each_menu: (menu, fun) ->
        _.each menu, (m) =>
            if m.menu
                @each_menu(m.menu.entries, fun)
            else if !m.divider
                fun(m)

    process_menu: (action, menu_name) ->
        processor = @menu_processors[menu_name]
        @each_menu action.meta.menus[menu_name].entries, (m) ->
            fun_name = "#{menu_name}_#{m.name}"
            fun_invoke = "action['#{fun_name}'](#{processor.arg_name})"
            fun_invoke = "(#{m.enabled}) && #{fun_invoke}" if m.enabled?
            fun_invoke = "!(#{m.disabled}) && #{fun_invoke}" if m.disabled?

            click = m.click
            m.click = fun_invoke

            if click
                action[fun_name] = (args...) ->
                    processor.arg_fun(action, args...)
                    action.scope().$eval(click)
            else
                action[fun_name] ?= (args...) ->
                    processor.arg_fun(action, args...)
                    args = processor.arg_ret(action)
                    _.merge(args, $parse(m.arguments)(action.scope())) if m.arguments?
                    action.invoke_action(m.name, args)

            if action.find_action_info(m.name, false)?
                show = if m.show then " && " + m.show else ""
                m.show = "action.find_action_info('#{m.name}').access" + show

    menu_processors:
        menu:
            arg_name: ''
            arg_fun: (action) ->
            arg_ret: (action) -> {}
        panel_menu:
            arg_name: ''
            arg_fun: (action) ->
            arg_ret: (action) -> {}
        item_menu:
            arg_name: '$index'
            arg_ret: (action) -> id: action.current_id()
            arg_fun: (action, index) -> action.current_index = index

    renderers:
        boolean: (value, render) =>
            switch value
                when render.true_value then E2Snippets.boolean_true_value
                when render.false_value then E2Snippets.boolean_false_value
                else "?"
        list_select: (value, render) ->
            render.list_hash ||= render.list.reduce(((h, [a, b]) -> h[a] = b; h), {})
            render.list_hash[value] ? value
        datetime: (value, render) ->
            value.split('\.')[0]
            # $dateFormatter.formatDate(value, "yyyy-MM-dd", $dateFormatter.getDefaultLocale())
        integer: (value, render) -> # ?
            value.toString()
        decimal_date: (value, render) ->
            value = value.toString()
            if value.length == 8 && match = value.match(/^(\d{4})(\d{2})(\d{2})$/) then match.slice(1, 4).join('-') else value
            # if value.length == 8 then $dateFormatter.formatDate(value, "yyyy-MM-dd", $dateFormatter.getDefaultLocale()) else value
        decimal_time: (value, render) ->
            value = value.toString()
            if match = value.match(/^(\d{1,2}?)(\d{2})(\d{2})$/) then match.slice(1, 4).join(':') else value
        string: (value, render) ->
            value.toString()


    render_field: (entry, name, meta) ->
        value = entry[name]
        if value? && info = meta.info
            f_info = info[name]
            if f_info? && type = f_info.type
                @renderers[type](value, f_info.render)
            else
                if f_info?.escape == false then value else
                    (value + "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        else
            value

    parsers:
        integer: (value, info) ->
            parseInt(value)

    parse_entry: (value, info) ->
        parser = @parsers[info.type]
        if parser then parser(value, info) else value

.provider '$e2Modal', ->
    $get: ($rootScope, $modal, $timeout, $window, $injector) ->
        class MManager
            @Z_INDEX: 1050
            @index: 0
            constructor: () ->
            backdrop_z_index: (num, index) -> angular.element(document.querySelectorAll('.modal-backdrop')).eq(num).css('z-index', index)
            modal_num: (num) -> angular.element(document.querySelectorAll('.modal')).eq(num)
            backdrop: -> 'static'
            show_before: ->
                @z_index = MManager.Z_INDEX + MManager.index * 2
                @modal.css('z-index', @z_index + 1)
            hide_before: ->
                @z_index = MManager.Z_INDEX + ((MManager.index - 1) * 2)
            show: ->
            hide: -> angular.element($window.document.body).addClass('modal-open modal-with-am-fade') if MManager.index > 0

        class DefaultMManager extends MManager
            show_before: ->
                super()
                @backdrop.css('z-index', @z_index) # @backdrop_z_index(-MManager.index - 1, z_index)

        class FirstMManager extends MManager
            constructor: () ->
                super()
                @threshold = 2
            backdrop: -> if MManager.index > @threshold then false else super()
            show_before: ->
                super()
                if MManager.index > @threshold
                    @modal_num((MManager.index - 1) - @threshold).css('display', 'none')
                    @backdrop_z_index(0, @z_index)
                else
                    @backdrop.css('z-index', @z_index) # @backdrop_z_index(-MManager.index - 1, z_index)

            hide_before: ->
                super()
                if MManager.index > @threshold
                    @backdrop_z_index(0, @z_index)
                    @modal_num((MManager.index - 1) - @threshold).css('display', 'block')

        class SingleBackdropMManager extends MManager
            backdrop: -> if MManager.index > 0 then false else super()
            show_before: ->
                super()
                @backdrop_z_index(0, @z_index)
            hide_before: ->
                super()
                @backdrop_z_index(0, @z_index)

        is_modal: -> MManager.index > 0

        show: (action) ->
            scope = if action.scope then action.scope().$new(true) else $rootScope.$new()
            scope.action = action
            manager = new SingleBackdropMManager()

            scope.$on 'modal.show.before', (e, m) ->
                e.stopPropagation()
                manager.modal = m.$element
                manager.backdrop = m.$backdrop
                throw "Modal has element" if scope.action.element?()
                scope.action.element = -> m.$element
                scope.action.panel_show?()
                manager.show_before()
                MManager.index++

            scope.$on 'modal.show', (e, m) ->
                e.stopPropagation()
                manager.show()
                scope.action.panel_shown?()

            scope.$on 'modal.hide.before', (e) ->
                e.stopPropagation()
                MManager.index--
                manager.hide_before()
                scope.action.panel_hide?()

            scope.$on 'modal.hide', (e) ->
                e.stopPropagation()
                manager.hide()
                scope.action.panel_hidden?()
                scope.$destroy()

            $injector.get('E2').fetch_panel(scope.action.meta.panel, true).then (template) ->
                modal = $modal(scope: scope, template: template, backdrop: scope.action.meta.backdrop ? manager.backdrop(), animation: scope.action.meta.panel.animation ? 'am-fade', show: false)
                scope.action.modal_hide = -> modal.$scope.$hide()
                modal.$promise.then ->
                    modal.show()
                    modal

        error: (title, msg, html) ->
            body = if html then msg else "<div class='alert alert-danger'>#{msg}</div>"
            clazz = if html then "modal-huge" else "modal-large"
            @show meta: panel: (panel_template: "close_m", template_string: body, title: title, class: clazz, footer: true) # message: msg,

        confirm: (title, msg, action) ->
            body = "<div class='alert alert-warning'>#{msg}</div>"
            clazz = "modal-large"
            @show
                confirm: action,
                meta: panel: (panel_template: "confirm_m", template_string: body, title: title, class: clazz, footer: true) # message: msg,

.directive 'e2Modal', ($e2Modal) ->
    restrict: 'E'
    # replace: true
    # transclude: true
    scope: true
    compile: (celem, cattr) ->
        obody = celem[0].children[0]
        celem.empty() if obody
        (scope, elem, attrs) ->
            scope.$on attrs.name, (ev, args) ->
                return if ev.defaultPrevented
                ev.preventDefault()

                panel = panel_template: attrs.panelTemplate, title: attrs.title, class: attrs.clazz, footer: true
                if obody then panel.template_string = obody.outerHTML else panel.template = attrs.template
                action = meta: (panel: panel), scope: -> scope
                _.assign(action, args)

                modal = $e2Modal.show(action)
                hide_off = scope.$on "#{attrs.name}_close", ->
                    hide_off()
                    modal.then (m) -> m.$scope.$hide()

.directive 'e2Field', ($timeout, $filter) ->
    require: 'ngModel'
    restrict: 'A'
    scope: false
    link: (scope, elem, attrs, controller) ->
        scope.$on "$destroy", -> elem.off()

        name = attrs.e2Field || scope.f
        meta = scope.action.meta
        info = meta.info[name]
        scope.$on "focus_field", (event, n, mode) ->
            if n == name
                elem[0].focus()

        if info.onfocus
            elem.on 'focus', ->
                # scope.$apply(-> scope.$eval(info.onfocus))
                $timeout -> scope.$apply(info.onfocus)

        if elem[0].type in ['text', 'password']
            elem.on 'keypress', (ev) ->
                scope.$apply ->
                    # scope.action.panel_menu_save() if ev.keyCode == 13 # && elem[0].type != 'textarea'
                    scope.$emit "return_pressed" if ev.keyCode == 13 # && elem[0].type != 'textarea'
                ev.stopPropagation()

            if info.filter
                filter = $filter(info.filter)
                controller.$parsers.push (value) ->
                    filtered = filter(value)
                    controller.$setViewValue(filtered)
                    controller.$render()
                    filtered
                scope.action.record[name] = filter(scope.action.record[name])

.directive 'e2SearchField', ($timeout, $filter) ->
    require: 'ngModel'
    restrict: 'A'
    scope: false
    link: (scope, elem, attrs, controller) ->
        name = attrs.e2Field || scope.f
        meta = scope.action.meta
        info = meta.info[name]
        if info.filter
            filter = $filter(info.filter)
            controller.$parsers.push (value) ->
                filtered = filter(value)
                controller.$setViewValue(filtered)
                controller.$render()
                filtered
            scope.action.query.search[name] = filter(scope.action.query.search[name])

.directive 'e2Include', ($parse, $compile, $http, $templateCache) ->
    restrict: 'E'
    # replace: true
    # terminal: true
    scope: false
    link: (scope, elem, attrs) ->
        name = $parse(attrs.template)(scope)
        $http.get(name, cache: $templateCache).success (body) ->
            # elem.html($compile(body)(scope))
            # elem.replaceWith($compile(body)(scope))
            elem.empty()
            elem.after($compile(body)(scope))

.directive 'e2TableBody', ($parse, $compile) ->
    scope: false
    restrict: 'A'
    link: (scope, elem, attrs) ->
        scope.$on 'render_table', (a, ev) ->
            # ev.stopPropagation()
            meta = scope.action.meta
            selection = scope.action.selection
            out = ''
            _.each scope.action.entries, (e, i) ->
                out += if selection then "<tr ng-class='action.selected_class(#{i})' class='tr_hover' ng-click='action.select(#{i}, $event)'>" else
                    row_cls = e.$row_info?.class
                    if row_cls then "<tr class=\"#{row_cls}\">" else "<tr>"
                out += "<td>"
                out += "<div e2-button-set='action.meta.menus.item_menu' index='#{i}'></div>" if meta.config.show_item_menu
                out += "</td>"
                _.each meta.fields, (f) ->
                    out += if col_cls = meta.info[f].column_class then "<td class='#{col_cls}'>" else "<td>"
                    out += scope.action.list_cell(e, f) ? ''
                    out += "</td>"
                out += "</tr>"

            elem.empty()
            elem.append($compile(out)(scope)) unless out.length == 0 # leak ?

.directive 'e2Dropdown', ($parse, $dropdown, $timeout, E2Snippets) ->
    event_num = 0
    dropdown_sub_tmpl = _.template("<li class='dropdown-submenu'><a href=''> {{icon}}{{aicon}} {{loc}}</a>{{sub}}</li>")
    dropdown_tmpl = _.template("<li {{clazz}} {{show}} {{hide}}> <a href='{{href}}' {{click}}> {{icon}}{{aicon}} {{loc}}</a></li>")

    render = (menu, level) ->
        out = menu.map (m) ->
            switch
                when m.divider
                    "<li class='divider'></li>"
                when m.menu
                    dropdown_sub_tmpl
                        icon: m.menu.icon && E2Snippets.icon(m.menu.icon) || ''
                        aicon: m.menu.aicon && E2Snippets.aicon(m.menu.aicon) || ''
                        loc: m.menu.loc
                        sub: render(m.menu.entries)
                else
                    dropdown_tmpl
                        clazz: E2Snippets.make_ng_class(m)
                        show: m.show && "ng-show=\"#{m.show}\"" || ''
                        hide: m.hide && "ng-hide=\"#{m.hide}\"" || ''
                        href: m.href || ''
                        click: m.click && "ng-click=\"#{m.click}\"" || ''
                        icon: m.icon && E2Snippets.icon(m.icon) || ''
                        aicon: m.aicon && E2Snippets.aicon(m.aicon) || ''
                        loc: m.loc
        "<ul class='dropdown-menu'>#{out.join('')}</ul>"

    scope: false
    link: (scope, elem, attrs) ->
        scope.$on "$destroy", -> elem.off()
        hook = (event) ->
            event_num++
            elem.addClass "active"
            elem.off "mousedown"
            # event.preventDefault()
            # event.stopPropagation()
            menu = $parse(attrs.e2Dropdown)(scope)
            dropdown = $dropdown(elem, (scope: scope, template: render(menu, 0), animation: attrs.animation || 'am-flip-x', prefixEvent: "#{event_num}.tooltip")) # , delay: 1
            dropdown.$promise.then ->
                event_hide = scope.$on "#{event_num}.tooltip.hide", (e) ->
                    e.stopPropagation()
                    event_hide()
                    dropdown.destroy()
                    elem.on "mousedown", hook

                event_before = scope.$on "#{event_num}.tooltip.hide.before", (e) ->
                    e.stopPropagation()
                    event_before()
                    elem.removeClass "active"

        elem.on "mousedown", hook

.directive 'e2ButtonSet', ($parse, $compile, E2Snippets) ->
    button_set_tmpl = _.template("<div class='btn btn-default' {{clazz}} {{click}} {{show}} {{hide}} {{title}}> {{icon}}{{aicon}} {{loc}}</div>")
    button_set_arr_tmpl = _.template("<div class='btn btn-default' e2-dropdown='{{dropdown}}' data-animation='{{animation}}'>{{icon}}{{aicon}}<span class='caret'></span></div>")
    scope: true # because $index
    link: (scope, elem, attrs) ->
        menu = $parse(attrs.e2ButtonSet)(scope)
        if menu && menu.entries.length > 0
            group_class = menu.properties.group_class || ''
            brk = menu.properties.break
            animation = menu.properties.animation
            out = ""
            for m, i in menu.entries
                if i >= brk
                    break
                else if m.menu
                    out += button_set_arr_tmpl
                        dropdown: "#{attrs.e2ButtonSet}.entries[#{i}].menu.entries"
                        animation: animation
                        icon: m.menu.icon && "#{E2Snippets.icon(m.menu.icon)}&nbsp;" || ''
                        aicon: m.menu.aicon && "#{E2Snippets.aicon(m.menu.aicon)}&nbsp;" || ''
                else if m.divider
                else
                    out += button_set_tmpl
                        clazz: E2Snippets.make_ng_class(m)
                        click: m.click && "ng-click=\"#{m.click}\"" || ''
                        show: m.show && "ng-show=\"#{m.show}\"" || ''
                        hide: m.hide && "ng-hide=\"#{m.hide}\"" || ''
                        icon: m.icon && E2Snippets.icon(m.icon) || ''
                        aicon: m.aicon && E2Snippets.aicon(m.aicon) || ''
                        loc: !(m.button_loc == false) && m.loc || ''
                        title: (m.button_loc == false) && "title=\"#{m.loc}\"" || ''

            if menu.entries.length > brk
                out += button_set_arr_tmpl
                    dropdown: "#{attrs.e2ButtonSet}.entries.slice(#{brk})"
                    animation: animation
                    icon: ''
                    aicon: ''

            out = "<div class='btn-group #{group_class}'>#{out}</div>"
            out = $compile(angular.element(out))(scope)
            if attrs.index && !scope.$index?
                scope.$index = attrs.index | 0
            # scope.data = attrs.data
            elem.after(out) # elem.append(out) # elem.replaceWith(out)

.directive 'e2InputCols', ($parse) ->
    clazz_cache = {}
    get_class = (len) ->
        if clazz = clazz_cache[len] then clazz else
            tab = switch         # lg md sm sx
                when len <= 2 then [2,2,4,6]
                when len <= 8 then [4,4,4,6]
                when len <= 20 then [6,7,7,7]
                when len <= 50 then [10,12,12,12]
                else [12,12,12,12] # ?
            clazz_cache[len] = _.zip(["lg", "md", "sm", "xs"], tab).map(([k, v]) -> "col-#{k}-#{v}").join(" ")

    scope: false
    link: (scope, elem, attrs, controller) ->
        elem.addClass get_class($parse(attrs.e2InputCols)(scope) | 0)

.directive 'e2Datepicker', ($parse, $dateFormatter) ->
    format = (value, fmt) -> # inline ?
        date = $dateFormatter.formatDate(value, fmt, $dateFormatter.getDefaultLocale())
        date = if date == undefined then "invalid" else date

    parse = (value, info) ->
        return unless value?
        value = value.toString()
        switch info.type
            when "decimal_time"
                if match = value.match(/^(\d{1,2}?)(\d{2}?)(\d{2}?)$/)
                    [h, m, s] = match.slice(1, 4) # .join(':')
                    date = new Date(); date.setHours(h); date.setMinutes(m); date.setSeconds(s)
                    date
                else value
            when "decimal_date"
                match = value.match(/^(\d{4}|\d{2})(\d{2})(\d{2})$/)
                if match then match.slice(1, 4).join('-') else value
            else value

    scope: true
    require: 'ngModel'
    link: (scope, element, attr, controller) ->
        action = scope.action
        mode = attr.e2Datepicker
        field = scope.other_date ? scope.other_time ? scope.f
        info = action.meta.info[field]

        if action.query
            scope.value[mode] = parse(action.query.search[scope.f][mode], info)
            scope.$on "search_reset", -> scope.value[mode] = null
        else
            value = parse(action.record[field], info)
            if mode then scope.value[mode] = value else scope.value = value

        scope.$watch attr.ngModel, (model, o) -> if model != o
            date = format(model, attr.e2ModelFormat)
            if action.query
                action.query.search[scope.f][mode] = date
                scope.action.search_field_change(scope.f) if date?
            else
                action.record[field] = date

.directive 'e2Integer', ->
    require: 'ngModel'
    link: (scope, elem, attr, controller) ->
        controller.$parsers.unshift (v) ->
            vs = v.toString()
            if vs.match(/^\-?\d+$/) then parseInt(vs) else (if scope.action.query? then null else vs)
