exports.config =
  npm:
    enabled: true
    globals:
        _: 'lodash'
        angular: 'angular'
    styles:
        "bootstrap": ["dist/css/bootstrap.css"]
        "bootstrap-additions": ["dist/bootstrap-additions.css"]
        "angular-motion": ["dist/angular-motion.css"]
        "angular-ui-tree": ["dist/angular-ui-tree.css"]
        "fork-awesome": ["css/fork-awesome.css"]
        # "ui-select": ["dist/select.css"]

  modules:
    definition: 'commonjs'
    wrapper: false
    nameCleaner: (path) -> path

  paths:
    public: 'public'
    watched: ['app']

  files:
    javascripts:
      joinTo:
        'assets/engine2vendor.js': /^node_modules|bower_components/
        'assets/engine2.js': /^app/
      order:
        before: [
          "app/engine2.coffee"
        ]

    stylesheets:
      joinTo:
        'assets/engine2vendor.css': /^(?:node_modules||bower_components)\/(?!(bootstrap\/))/
        'assets/bootstrap.css': /^node_modules\/(bootstrap\/)/
        'assets/engine2.css': /^app/
      # order:
      #   before: [
      #     /bootstrap\.css$/
      #   ]

  plugins:
    on: ["ng-annotate-brunch"]

    uglify:
      mangle: true
      compress:
        global_defs:
          DEBUG: false

    replacement:
      replacements: [
        files: [/vendor\.js$/]
        match: (
            fix = "$modal.$element = compileData.link(modalScope, function(clonedElement, scope) {});"
            find: fix.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1")
            replace: "#{fix}$modal.$backdrop = backdropElement;"
        )
        # files: [/\.css$/]
        # match: (
        #     find: "../fonts"
        #     replace: "fonts"
        # )
      ]

    copycat:
      fonts: [
        "node_modules/fork-awesome/fonts"
        "node_modules/bootstrap/fonts"
      ]
      verbose: true
      onlyChanged: true
