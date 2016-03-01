# coding: utf-8

Encoding.default_external = "utf-8"

require 'tilt/coffee' # eager
require 'bundler'
Bundler.require

load './lib/engine2.rb'

class App < Sinatra::Base
    # use Rack::Webconsole
    set :slim, pretty: true, sort_attrs: false
    set :views, ["#{APP_LOCATION}/views", 'views']
    set :sessions, expire_after: 3600 # , :httponly => true, :secure => production?
    # set :sessions, expire_after: 2

    helpers do
        def find_template(views, name, engine, &block)
            views.each{|v| super(v, name, engine, &block)}
        end
    end

    configure :development do
        # register Sinatra::Cache
        # set :cache_enabled, true
        # set :cache_output_dir, Proc.new { File.join(root, 'public', 'cache') }
        # Slim::Engine.set_default_options pretty: true, sort_attrs: false
    end

    use Engine2::Handler
    Engine2.bootstrap # if production ?

    get "/js/*.js" do |c|
        coffee c.to_sym
    end

    get '/*' do |name|
        headers 'Cache-Control' => 'no-cache, no-store, must-revalidate', 'Pragma' => 'no-cache', 'Expires' => '0'
        if name.empty?
            if settings.environment == :development
                t = Time.new
                load './lib/engine2.rb'
                Engine2.bootstrap
                puts "STARTUP: #{Time.new - t}"
            end
            name = 'index'
        end
        slim name.to_sym
    end
end
