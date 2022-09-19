'use strict'
require 'angular-sanitize'
require 'angular-animate'
require 'angular-cookies'
require 'angular-local-storage'
require 'angular-ui-tree'
require '@uirouter/core'
require '@uirouter/angularjs'
require 'ng-file-upload'
require 'angular-load'
require 'angular-drag-and-drop-lists'
# require 'ui-select'

_.templateSettings.interpolate = /{{([\s\S]+?)}}/g;

angular.module('Engine2', ['ngSanitize', 'ngAnimate', 'ngCookies', 'mgcrea.ngStrap', 'ngFileUpload', 'ui.tree', 'LocalStorageModule', 'angularLoad', 'ngWebSocket', 'ui.router', 'dndLists', 'toastr']) # 'ui.select'
.config ($httpProvider, $compileProvider, localStorageServiceProvider, $logProvider, $qProvider, $locationProvider, $provide) ->
    $httpProvider.interceptors.push 'e2HttpInterceptor'
    $provide.decorator '$httpBackend', ($delegate) ->
        (method, url, post, callback, headers, timeout, withCredentials, responseType) ->
            url = url.replace(/;/g, '%3B') unless method == 'POST'
            $delegate(method, url, post, callback, headers, timeout, withCredentials, responseType)
    # $httpProvider.defaults.headers.common['Cache-Control'] = 'no-cache'
    # $httpProvider.defaults.cache = false;
    $httpProvider.defaults.headers.get ?= {} # if !$httpProvider.defaults.headers.get
    $httpProvider.defaults.headers.get['If-Modified-Since'] = '0'
    # localStorageServiceProvider.setStorageType('sessionStorage')
    localStorageServiceProvider.setPrefix('E2')
    $compileProvider.debugInfoEnabled(false)
    $logProvider.debugEnabled(true)
    $httpProvider.useApplyAsync(true)
    # $qProvider.errorOnUnhandledRejections(false)
    # $locationProvider.hashPrefix('')
    # $locationProvider.html5Mode(false)
    $provide.decorator 'ngModelDirective', ($delegate) ->
        directive = $delegate[0]
        compile = directive.compile
        directive.compile = (elem, attrs, trans) ->
            comp = compile(elem, attrs, trans)
            pre: comp.pre
            post: (scope, element, attr, ctrls) ->
                ctrls[0].$parsers.push (vw) -> if vw == "" then null else vw
                comp.post(scope, element, attr, ctrls)
        $delegate

.factory 'PushJS', -> require 'push.js'
.factory 'PrettyYAML', -> require 'json-to-pretty-yaml'
.filter 'yaml', (PrettyYAML) -> (input) -> PrettyYAML.stringify(input, 4)

.factory 'MetaCache', ($cacheFactory) -> $cacheFactory('MetaCache')
.factory 'e2HttpInterceptor', ($q, $injector, E2Snippets) ->
    loaderToggle = (toggle) -> angular.element(document.querySelectorAll('.loader')).eq(-1).css("visibility", toggle)
    loaderOn = -> loaderToggle('visible')
    timeout = null
    loaderOff = ->
        if timeout
            clearTimeout timeout
            timeout = null
            loaderToggle('hidden')

    request: (request) ->
        if timeout
            clearTimeout timeout
            timeout = null
        else
            timeout = setTimeout(loaderOn, 200)
        request

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
    icon = (name) ->
        if name.slice(0, 3) == 'fa_'
            "<i class='fa fa-#{name.slice(3)}'></i>"
        else if (idx = name.indexOf('.')) != -1
            "<img src=#{name}></img>"
        else
            "<span class='glyphicon glyphicon-#{name}'></span>"

    ng_class_names = ['active', 'enabled', 'disabled']
    icon: icon
    boolean_true_value:     icon('check')
    boolean_false_value:    icon('unchecked')
    make_ng_class: (o) ->
        out = []
        _.each ng_class_names, (e) -> out.push(if e == 'enabled' then "'disabled': !(#{o[e]})" else "'#{e}': #{o[e]}") if o[e]?
        _.each(o.class, (v, k) -> out.push "'#{k}': #{v}") if o.class?
        if out.length > 0 then "ng-class=\"{#{out.join(',')}}\"" else ""

.factory 'E2', ($templateCache, $http, E2Snippets, $q, $dateFormatter, $parse, PushJS, $state, $e2Modal, toastr, $window) ->
    globals:
        element: (id) ->
            element = document.querySelector(id)
            console.warn "Element #{id} not found" unless element
            element

        notification: (name, body, icon, timeoutx, on_close) ->
            PushJS.create name, body: body, icon: icon, timeout: timeoutx, onClick: on_close

        toastr: -> toastr
        state: -> $state
        modal: -> $e2Modal
        window: -> $window

    uuid: (length) ->
        Math.random().toString(10).substr(2, 8)

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
                o[k] = null # delete o[k]

    merge_meta: (dst, src) ->
        for k, v of src
            throw "Attempted to override function '#{k}'" if _.isFunction(dst[k])
            if (k == 'execute' || k == 'pre_execute') && dst[k] && src[k]
                dst[k] = dst[k].concat(src[k])
            else
                insn = k.slice(-1)
                if _.isObject(v) && !_.isArray(v)
                    if insn == '!' then dst[k.slice(0, -1)] = v else dst[k] = @merge_meta(dst[k] ? {}, v)
                else
                    if insn == '?' then dst[k.slice(0, -1)] ?= v else dst[k] = v
        dst

    transpose: (a) ->
        _.keys(a[0]).map((c) -> a.map (r) -> r[c])

    join_keys: (keys) -> keys.join(@globals.key_separator)
    split_keys: (key) -> key.split(@globals.key_separator)
    id_for: (rec, meta) -> @join_keys(meta.primary_fields.map((e) -> rec[e]))
    from_id: (id, meta) -> _.zipObject(meta.primary_fields, id) # _.zip(meta.primary_fields, id).reduce(((rec, [k, v]) -> rec[k] = v; rec), {})

    icon: E2Snippets.icon

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
                action[fun_name] = (arg) ->
                    processor.arg_fun(action, arg)
                    action.scope().$eval(click)
            else
                if ofun = action[fun_name]
                    action["#{fun_name}_super"] = (args) ->
                        _.merge(args, $parse(m.arguments)(action.scope())) if m.arguments?
                        action.invoke_action(m.name, args)

                    action[fun_name] = (args) ->
                        processor.arg_fun(action, args)
                        args = processor.arg_ret(action)
                        ofun.bind(action)(args)
                else
                    action[fun_name] = (arg) ->
                        processor.arg_fun(action, arg)
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
            arg_fun: (action, index) -> action.current_index = index
            arg_ret: (action) -> id: action.current_id()

    renderers:
        boolean: (value, render) =>
            switch value
                when render.true_value then E2Snippets.boolean_true_value
                when render.false_value then E2Snippets.boolean_false_value
                else value
        list_select: (value, render, separator) ->
            render.list_hash ||= render.values.reduce(((h, [a, b]) -> h[a] = b; h), {})
            if render.multiselect && _.isArray(value)
                value.map((v) -> render.list_hash[v] ? ":#{value}:").join(separator)
            else
                render.list_hash[value] ? ":#{value}:"
        datetime: (value, render) ->
            value.split('\.')[0].split(' ', 2).join(' ')
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


    render_field: (entry, name, meta, separator) ->
        value = entry[name]
        if value? && info = meta.fields
            f_info = info[name]
            if f_info? && type = f_info.type
                @renderers[type](value, f_info.render, separator)
            else
                value = (value + "")
                value = value.replace(/\n/g, "<br>") if f_info?.html_br
                value = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") unless f_info?.escape == false
                value
        else
            value

    parsers:
        integer: (value, info) ->
            val = parseInt(value)
            if val.toString() == value then val else value

    parse_entry: (value, info) ->
        parser = @parsers[info.type]
        if parser then parser(value, info) else value

.directive 'e2Field', ($timeout, $filter) ->
    require: 'ngModel'
    restrict: 'A'
    scope: false
    link: (scope, elem, attrs, controller) ->
        scope.$on "$destroy", -> elem.off()

        name = attrs.e2Field || scope.f
        meta = scope.action.meta
        info = meta.fields[name]
        scope.$on "focus_field", (event, n, mode) ->
            if n == name && !info.dont_focus
                elem[0].focus()

        if info.onfocus
            elem.on 'focus', ->
                # scope.$apply(-> scope.$eval(info.onfocus))
                $timeout -> scope.$apply(info.onfocus)

        if elem[0].type in ['text', 'password']
            elem.on 'keypress', (ev) ->
                scope.$apply ->
                    scope.action.panel_menu_default_action?() if ev.keyCode == 13

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
        info = meta.fields[name]
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
        $http.get(name, cache: $templateCache).then (response) ->
            # elem.html($compile(body)(scope))
            # elem.replaceWith($compile(body)(scope))
            elem.empty()
            elem.after($compile(response.data)(scope))

.directive 'e2TableBody', ($parse, $compile) ->
    table_tmpl = _.template("<thead><tr>{{thead}}</tr></thead><tbody {{tbody_attrs}}>{{tbody}}</tbody><tfoot><tr>{{tfoot}}</tr></tfoot>")
    scope: false
    restrict: 'A'
    link: (scope, elem, attrs) ->
        table_scope = null
        scope.$on 'render_table', (a, ev) ->
            # ev.stopPropagation()
            table_scope.$destroy() if table_scope
            table_scope = scope.$new(false)

            action = table_scope.action
            meta = action.meta
            draggable = meta.draggable
            position = meta.menus.item_menu.properties.position ? 0
            right_style = if position >= meta.field_list.length then "style=\"text-align: right\"" else ""

            thead = ""
            fields = meta.field_list.slice()
            fields.splice(position, 0, null)
            _.each fields, (f) ->
                if f
                    info = meta.fields[f]
                    thead += if col_cls = meta.fields[f].column_class then "<th class=\"#{col_cls}\">" else "<th>"
                    title = if info.title then "title=\"#{info.title}\"" else ""
                    if info.sort
                        thead += "<a ng-click=\"action.order('#{f}')\" #{title}><strong>#{info.loc}</strong></a>"
                        thead += if action.ui.order == f
                            up_down = if action.ui.asc then "up" else "down"
                            if action.meta.sort_icon_up && action.meta.sort_icon_down
                                " #{action.meta['sort_icon_' + up_down]}"
                            else
                                " <span class=\"fa fa-arrow-#{up_down}\"></span>"
                        else
                            " <span class=\"fa fa-sort\"></span>"
                    else
                        thead += "<span #{title}>#{info.loc}</span>"
                    thead += "</th>"
                else
                    thead += "<th class=\"#{meta.menus.menu.properties.class || ''}\" #{right_style}><div e2-button-set=\"action.meta.menus.menu\"></div></th>"

            tbody = ""
            _.each action.entries, (e, i) ->
                tbody += if action.selection then "<tr ng-class=\"action.selected_class(#{i})\" class=\"tr_hover\" ng-click=\"action.select(#{i}, $event)\">" else
                    row_cls = e.$row_info?.class
                    tr_attrs = if draggable then "dnd-draggable=\"action.entries[#{i}]\" dnd-dragstart=\"action.entry_moved(#{i})\"" else ''
                    if row_cls then "<tr class=\"#{row_cls}\" #{tr_attrs}>" else "<tr #{tr_attrs}>"
                _.each fields, (f) ->
                    if f
                        tbody += if col_cls = meta.fields[f].column_td_class then "<td class=\"#{col_cls}\">" else "<td>"
                        tbody += action.list_cell(e, f) ? ''
                        tbody += "</td>"
                    else
                        tbody += "<td #{right_style}><div e2-button-set=\"action.meta.menus.item_menu\" index=\"#{i}\"></div></td>"
                tbody += "</tr>"

            tbody_attrs = if draggable then 'dnd-list=\"action.entries\" dnd-drop=\"action.entry_dropped(index, external, type)\"' else ''
            elem.empty()
            elem.append($compile(table_tmpl thead: thead, tbody: tbody, tbody_attrs: tbody_attrs, tfoot: "<e2-include template=\"'scaffold/pager'\"></e2-include>")(table_scope))

.directive 'e2Dropdown', ($parse, $dropdown, $timeout, E2Snippets) ->
    event_num = 0
    dropdown_sub_tmpl = _.template("<li class='dropdown-submenu' {{show}} {{hide}}><a href=''> {{icon}} {{loc}}</a>{{sub}}</li>")
    dropdown_tmpl = _.template("<li {{clazz}} {{show}} {{hide}} {{active}}> <a {{href}} {{click}}> {{icon}} {{loc}}</a></li>")

    render = (menu, nav) ->
        out = menu.map (m) ->
            switch
                when m.divider
                    "<li class='divider'></li>"
                when m.menu
                    dropdown_sub_tmpl
                        icon: m.menu.icon && E2Snippets.icon(m.menu.icon) || ''
                        loc: m.menu.loc
                        show: m.menu.show && "ng-show=\"#{m.menu.show}\"" || ''
                        hide: m.menu.hide && "ng-hide=\"#{m.menu.hide}\"" || ''
                        sub: render(m.menu.entries, nav)
                else
                    dropdown_tmpl
                        clazz: E2Snippets.make_ng_class(m)
                        show: m.show && "ng-show=\"#{m.show}\"" || ''
                        hide: m.hide && "ng-hide=\"#{m.hide}\"" || ''
                        href: m.href && "#{if nav then 'ui-sref' else 'href'}=\"#{m.href}\"" || ''
                        active: nav && "ui-sref-active='active'" || ''
                        click: m.click && "ng-click=\"#{m.click}\"" || ''
                        icon: m.icon && E2Snippets.icon(m.icon) || ''
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
            dropdown = $dropdown(elem, (scope: scope, template: render(menu, attrs.nav?), animation: attrs.animation || 'am-flip-x', prefixEvent: "#{event_num}.tooltip")) # , delay: 1
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
    button_set_tmpl = _.template("<a class='btn btn-default' {{href}} {{clazz}} {{click}} {{show}} {{hide}} {{title}}> {{icon}} {{loc}}</a>")
    button_set_arr_tmpl = _.template("<div class='btn btn-default' e2-dropdown='{{dropdown}}' data-animation='{{animation}}'>{{icon}}<span class='caret'></span></div>")
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
                else if m.divider
                else
                    out += button_set_tmpl
                        href: m.href && "href=\"#{m.href}\"" || ''
                        clazz: E2Snippets.make_ng_class(m)
                        click: m.click && "ng-click=\"#{m.click}\"" || ''
                        show: m.show && "ng-show=\"#{m.show}\"" || ''
                        hide: m.hide && "ng-hide=\"#{m.hide}\"" || ''
                        icon: m.icon && E2Snippets.icon(m.icon) || ''
                        loc: !(m.button_loc == false) && m.loc || ''
                        title: if m.title then "title=\"#{m.title}\"" else ((m.button_loc == false) && "title=\"#{m.loc}\"" || '')

            if menu.entries.length > brk
                out += button_set_arr_tmpl
                    dropdown: "#{attrs.e2ButtonSet}.entries.slice(#{brk})"
                    animation: animation
                    icon: ''

            out = "<div class='btn-group #{group_class}'>#{out}</div>"
            out = $compile(angular.element(out))(scope)
            if attrs.index && !scope.$index?
                scope.$index = attrs.index | 0
                scope.$entry = scope.action.entries[scope.$index]
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
            else
                match = value.match(/(.*)(?:\s[-+]\d+)$/)
                if match then match[1] else value

    scope: true
    require: 'ngModel'
    link: (scope, element, attr, controller) ->
        action = scope.action
        mode = attr.e2Datepicker
        has_mode = !_.isEmpty(mode)
        field = scope.other_date ? scope.other_time ? scope.f
        info = action.meta.fields[field]

        if action.query
            f = action.query.search[scope.f]
            if has_mode
                scope.value[mode] = parse(f[mode], info)
                scope.$on "search_reset", -> scope.value[mode] = null
            else
                scope.value.at = parse(f, info)
                scope.$on "search_reset", -> scope.value.at = null
        else
            value = parse(action.record[field], info)
            if has_mode then scope.value[mode] = value else scope.value = value

        scope.$watch attr.ngModel, (model, o) -> if model != o
            date = format(model, attr.e2ModelFormat)
            if action.query
                if has_mode then action.query.search[scope.f][mode] = date else action.query.search[scope.f] = date
                scope.action.search_field_change(scope.f) if date?
            else
                action.record[field] = date

.directive 'e2Integer', ->
    require: 'ngModel'
    link: (scope, elem, attr, controller) ->
        controller.$parsers.unshift (v) ->
            vs = v.toString()
            if vs.match(/^\-?\d+$/) then parseInt(vs) else (if scope.action.query? then null else vs)
