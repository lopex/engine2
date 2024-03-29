# coding: utf-8
# frozen_string_literal: true

module Engine2
    class Handler < Sinatra::Base
        reset!
        API_PATH ||= "/api"
        VIEWS_PATH ||= "/views"
        ENGINE2_REQUEST_HEADER ||= "HTTP_ENGINE2_REQUEST_HEADER"

        def no_cache_headers
            headers 'Cache-Control' => 'no-cache, no-store, must-revalidate', 'Pragma' => 'no-cache', 'Expires' => '0'
        end

        def halt_json code, cause, message
            halt code, {'Content-Type' => 'application/json'}, {message: message, cause: cause}.to_json
        end

        def halt_forbidden cause = '', message = LOCS[:access_forbidden]
            halt_json 403, cause, message
        end

        def halt_unauthorized cause = '', message = LOCS[:access_unauthorized]
            halt_json 401, cause, message
        end

        def halt_not_found cause = '', message = LOCS[:access_not_found]
            halt_json 404, cause, message
        end

        def halt_method_not_allowed cause = '', message = LOCS[:access_method_not_allowed]
            halt_json 405, cause, message
        end

        def halt_server_error cause, message
            halt_json 500, cause, message
        end

        def permit access
            settings.development? ? raise(E2Error.new("Permission denied")) : halt_forbidden('Permission denied') unless access
        end

        def initial?
            params[:initial]
        end

        def decode_id id
            IdEncoder.split_keys(params[id])
        end

        def logged_in?
            !user.nil?
        end

        def user
            session[:user]
        end

        def no_cache
            # agent = request.user_agent
            # if agent && (agent["MSIE"] || agent["Trident"])
            #     headers["Pragma"] = "no-cache"
            #     headers["Expires"] = "0"
            #     headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
            # end
        end

        def post_to_json
            JSON.parse(request.body.read, symbolize_names: true) # rescue halt_server_error
        end

        def param_to_json name
            permit param = params[name]
            JSON.parse(param, symbolize_names: true) # rescue halt_server_error
        end

        def serve_api_resource verb, path
            path = path.split('/') # -1 ?
            is_meta = path.pop if path.last == 'meta'
            node = ROOT
            path.each do |pat|
                node = node[pat.to_sym]
                halt_not_found unless node
                halt_unauthorized unless node.check_access!(self)
            end

            action = node.*
            response = if is_meta
                params[:access] ? node.access_info(self) : {meta: action.meta, actions: node.nodes_info(self)}
            else
                if action.http_method == verb && action.invokable
                    begin
                        action.invoke!(self)
                    rescue => error
                        attachment nil, nil
                        # content_type :json
                        serve_api_error(error)
                    end
                else
                    halt_method_not_allowed
                end
            end

            if response.is_a?(Hash)
                content_type :json
                response.to_json
            else
                response
            end
        end

        [:get, :post, :delete].each do |verb|
            send(verb, "#{API_PATH}/*"){|path| serve_api_resource(verb, path)}
        end

        def serve_api_error error
            halt_server_error Rack::Utils.escape_html(error.inspect) + "<hr>" + error.backtrace.take(30).map{|b| Rack::Utils.escape_html(b)}.join("<br>"), LOCS[:error]
        end

        get "#{VIEWS_PATH}/*" do |name|
            # pass unless request.env[ENGINE2_REQUEST_HEADER]
            no_cache_headers
            slim name.to_sym
        end

        get '/' do
            if settings.development?
                load('engine2.rb') if Engine2::SETTINGS[:reloading]
                Engine2::reload
            end
            no_cache_headers
            slim :index
        end

        set :slim, pretty: !production?, sort_attrs: false
        unless production? # use Engine2::SETTINGS[:reloading] ?
            set :sessions, expire_after: 3600
            # set :session_store, Rack::Session::Pool
        end

        helpers do
            def find_template(views, name, engine, &block)
                views.each{|v| super(v, name, engine, &block)}
            end
        end
    end
end
