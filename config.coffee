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
        "font-awesome": ["css/font-awesome.css"]

  modules:
    definition: 'commonjs'
    wrapper: false

  paths:
    public: 'public'
    watched: ['app']

  files:
    javascripts:
      joinTo:
        'vendor.js': /^node_modules|bower_components/
        'app.js': /^app/

    stylesheets:
      joinTo:
        'vendor.css': /^node_modules/
        'app.css': /^app/
      order:
        before: [
          /bootstrap.css$/
        ]

  plugins:
    on: ["ng-annotate-brunch"]

    uglify:
      mangle: true
      compress:
        global_defs:
          DEBUG: false

    replacement:
      replacements: [
        files: [/vendor.js$/]
        match: (
            fix = "$modal.$element = compileData.link(modalScope, function(clonedElement, scope) {});"
            find: fix.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1")
            replace: "#{fix}$modal.$backdrop = backdropElement;"
          )
      ]

    copycat:
      fonts: [
        "node_modules/font-awesome/fonts"
        "node_modules/bootstrap/fonts"
      ]
      verbose: true
      onlyChanged: true
