'use strict'
angular.module('Engine2')
.provider '$e2Modal', ->
    $get: ($rootScope, $modal, $timeout, $window, $injector) ->
        class MManager
            @Z_INDEX: 1050
            @index: 0
            constructor: () ->
            backdrop_z_index: (num, index) -> angular.element(document.querySelectorAll('.modal-backdrop')).eq(num).css('z-index', index)
            modal_num: (num) -> angular.element(document.querySelectorAll('.modal')).eq(num)
            backdrop: (bdr) -> bdr ? 'static'
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
            backdrop: (bdr) -> if MManager.index > @threshold then false else super(bdr)
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
            backdrop: (bdr) -> if MManager.index > 0 then false else super(bdr)
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
                throw "Modal has element" if action.element?()
                action.element = -> m.$element
                action.panel_show?()
                manager.show_before()
                MManager.index++

            scope.$on 'modal.show', (e, m) ->
                e.stopPropagation()
                manager.show()
                action.panel_shown?()

            scope.$on 'modal.hide.before', (e) ->
                e.stopPropagation()
                MManager.index--
                manager.hide_before()
                action.panel_hide?()

            scope.$on 'modal.hide', (e) ->
                e.stopPropagation()
                manager.hide()
                action.panel_hidden?()
                scope.$destroy()

            $injector.get('E2').fetch_panel(action.meta.panel, true).then (template) ->
                modal = $modal
                    scope: scope
                    show: false
                    template: template
                    backdrop: manager.backdrop(action.meta.panel.backdrop)
                    animation: action.meta.panel.animation ? 'am-fade'

                action.modal_hide = -> modal.$scope.$hide()
                modal.$promise.then ->
                    modal.show()
                    modal

        show_modal: (title, msg, options = {html: false, alert_class: 'alert-danger', modal_class: 'modal-large'}) ->
            body = if options.html then msg else "<div class='alert alert-#{options.alert_class}'>#{msg}</div>"
            clazz = if options.html then "modal-huge" else options.modal_class
            @show meta: panel: (panel_template: "close_m", template_string: body, title: title, class: clazz, footer: true) # message: msg,


        info: (title, msg, options = {alert_class: 'info', modal_class: 'modal-large'}) -> @show_modal(title, msg, options)
        warning: (title, msg, options = {alert_class: 'warning', modal_class: 'modal-large'}) -> @show_modal(title, msg, options)
        error: (title, msg, options = {alert_class: 'danger', modal_class: 'modal-huge'}) -> @show_modal(title, msg, options)

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