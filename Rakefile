require 'bundler'
Bundler.require(:assets)

DIR = Dir.pwd
VIEWS = DIR + "/views"
PUBLIC = DIR + "/public"
COFFEE_FILES = ["app", "engine2", "engine2actions"]

desc "Compile JS"
task :compile_js do
    COFFEE_FILES.each do |cf|
        out = CoffeeScript.compile(open("#{VIEWS}/#{cf}.coffee", "r:UTF-8"))
        out = Uglifier.new(
            # mangle: false
            mangle: {except: %w|
                $injector
                $window
                $rootScope
                $scope
                $compile
                $routeProvider
                $compileProvider
                $locationProvider
                $location
                $route
                $parse
                $templateCache
                $resource
                $attrs
                $element
                $http
                $cookies
                $sanitize
                $timeout
                $httpProvider
                $logProvider
                $q
                $upload
                $dropdown
                $modal
                E2
                E2Snippets
                E2Actions
                E2ActionsX
                $e2Scaffold
                $e2Modal
                localStorageServiceProvider
                localStorageService
                $dateParser
                $dateFormatter
                $filter
                e2HttpInterceptor
            |}
        ).compile(out)
        open("#{PUBLIC}/js/#{cf}.js", "w") << out
    end
end

desc "Compile SLIM"
task :compile_slim do
    view_dirs = ["fields", "scaffold", "search_fields", "modals"]
    slims = view_dirs.each.map do |view_dir|
        Dir["views/#{view_dir}/*.slim"].map do |slim_file|
            slim = Slim::Template.new(slim_file).render.gsub('"', '\"')
            tpl_name =  slim_file.sub("views/", "").sub(".slim", "")
            "$templateCache.put('#{tpl_name}', \"#{slim}\");"
        end
    end

    open("#{PUBLIC}/js/engine2templates.js", "w") << <<-EOF
angular.module('Engine2').run(['$templateCache', function($templateCache) {
#{slims.join("\n")}
}]);
EOF
end

desc "Compile"
task :compile => [:compile_js, :compile_slim] do
end

desc "Clean"
task :clean do
    COFFEE_FILES.each do |js|
        File.delete "#{PUBLIC}/js/#{js}.js"
    end
end

desc "Assets Js"
task :assets_js do
    # jquery-builder.cmd -m -v 2.0.3 -e ajax,deprecated,effects,offset > jquery-custom.min.js
    # lodash modern category=arrays,collections,objects,chaining,lang plus=template

    js_files =  %w[
            angular-file-upload-shim.min.js
            angular.js
            i18n/angular-locale_pl.js
            angular-route.js
            angular-sanitize.js
            angular-animate.js
            angular-cookies.js
            angular-strap.js
            angular-strap.tpl.js
            angular-file-upload.min.js
            angular-ui-tree.js
            angular-local-storage.js
            lodash.custom.min.js
        ]

    out = js_files.map{|js| open("#{PUBLIC}/js/#{js}", "r:UTF-8").read}.join("")

    out = Uglifier.new(output: {comments: :none}, mangle: true).compile(out)
    out = YUI::JavaScriptCompressor.new(java: "#{ENV['JAVA_HOME']}/bin/java", munge: false).compress(out)

    open("#{PUBLIC}/assets/javascripts.js", "w") << out
end

desc "Assets Css"
task :assets_css do
    # app.css
    css_files =  %w[
            bootstrap-additions.css
            angular-motion.css
            angular-ui-tree.min.css
            font-awesome.min.css
        ]

    out = css_files.map{|css|open("#{PUBLIC}/css/#{css}", "r:UTF-8").read}.join("")

    out = YUI::CssCompressor.new(java: "#{ENV['JAVA_HOME']}/bin/java").compress(out)
    open("#{PUBLIC}/assets/styles.css", "w") << out

end

desc "Assets"
task :assets => [:assets_js, :assets_css] do
    # File.delete *Dir["#{Dir.pwd}/public/assets/*"]
end

