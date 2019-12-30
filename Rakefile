desc "Compile SLIM"
task :compile_slim do
    require 'slim'
    view_dirs = ["fields", "scaffold", "search_fields", "modals", "panels"]
    slims = view_dirs.each.map do |view_dir|
        Dir["views/#{view_dir}/*.slim"].map do |slim_file|
            slim = Slim::Template.new(slim_file).render.gsub('"', '\"')
            tpl_name =  slim_file.sub("views/", "").sub(".slim", "")
            "c.put('#{tpl_name}', \"#{slim}\");"
        end
    end

    open("app/templates.js", "wb") << <<-EOF
angular.module('Engine2').run(['$templateCache', function(c) {
#{slims.join("\n")}
}]);
EOF
end

desc "Compile"
task :compile => [:compile_slim] do
end

task :default => [:compile]
