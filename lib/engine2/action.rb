# coding: utf-8

module Engine2

    class Action < BasicObject
        ACCESS_FORBIDDEN ||= ->h{false}
        attr_reader :parent, :name, :number, :actions, :recheck_access
        attr_reader :meta_proc

        class << self
            attr_accessor :count

            def default_meta
                Class.new(InlineMeta){meta_type :inline}
            end
        end

        def initialize parent, name, meta_class, assets
            Action.count += 1
            @number = Action.count
            @parent = parent
            @name = name
            @meta = meta_class.new(self, assets)
            @actions = {}
        end

        def * &blk
            @meta_proc = @meta_proc ? @meta_proc.chain(&blk) : blk if blk
            @meta
        end

        alias :meta :*

        def access! &blk
            ::Kernel.raise E2Error.new("Access for action #{name} already defined") if @access_block
            @access_block = blk
        end

        def access_forbidden!
            access! &ACCESS_FORBIDDEN
        end

        def check_access! handler
        	!@access_block || @access_block.(handler)
        end

        def run_scheme name, *args, &blk
            result = instance_exec(*args, &SCHEMES[name])
            result.instance_eval(&blk) if blk
            result
        end

        def define_action name, meta_class = Action.default_meta, assets = {}, &blk
            ::Kernel.raise E2Error.new("Action #{name} already defined") if @actions[name]
            action = @actions[name] = Action.new(self, name, meta_class, assets)
            action.*.pre_run
            define_singleton_method! name do |&ablk| # forbidden list
                action.instance_eval(&ablk) if ablk
                action
            end
            action.instance_eval(&blk) if blk
            action.*.action_defined
            action
        end

        def define_action_meta name, meta_class = Action.default_meta, assets = {}, &blk
            define_action name, meta_class, assets do
                self.* &blk
            end
        end

        def define_action_invoke name, meta_class = Action.default_meta, assets = {}, &blk
            define_action name, meta_class, assets do
                self.*.define_invoke &blk
            end
        end

        def define_action_bundle name, *actions
            define_singleton_method!(name) do |&blk|
                if blk
                    actions.each{|a|__send__(a, &blk)} # if @actions[action] ?
                else
                    ActionBundle.new(self, actions)
                end
            end
        end

        def define_singleton_method! name, &blk
            class << self;self;end.instance_eval do # __realclass__
                define_method name, &blk
            end
        end

        def [] name
            @actions[name]
        end

        def actions_info handler
            info = actions.inject({}) do |h, (name, a)|
                meta = a.*
                act = {
                    meta_type: meta.meta_type,
                    method: meta.http_method,
                    number: a.number,
                    terminal: a.actions.empty?,
                    meta: !meta.get.empty?
                }

                act[:access] = true if !recheck_access && a.check_access!(handler)
                act[:recheck_access] = true if a.recheck_access

                act[:meta_class] = meta.class if Handler::development?
                h[name] = act
                h
            end

            info.first[1][:default] = true unless actions.empty?
            info
        end

        def access_info handler
            @actions.inject({}) do |h, (name, a)|
                h[name] = a.check_access!(handler)
                h
            end
        end

        def recheck_access!
            @recheck_access = true
        end

        def each_action &blk
            # no self
            @actions.each_pair do |n, a|
                a.each_action(&blk) if yield a
            end
        end

        def to_a_rec root = true, result = [], &blk # optimize
            if root && (yield self)
                result << self
                @actions.each_pair do |n, a|
                    if yield a
                        result << a
                        a.to_a_rec(false, result, &blk)
                    end
                end
            end
            result
        end

        def inspect
            "Action: #{@name}, meta: #{@meta.class}, meta_type: #{@meta.meta_type}"
        end

        def setup_action_tree
            time = ::Time.now

            model_actions = {}
            each_action do |action|
                if model = action.*.assets[:model]
                    model_name = model.name.to_sym
                    model.synchronize_type_info
                    model_actions[model_name] = action.to_a_rec{|a| !a.*.assets[:assoc]}
                    action.run_scheme(model_name) if SCHEMES[model_name, false]
                    false
                else
                    true
                end
            end

            each_action do |action|
                meta = action.*
                model = meta.assets[:model]
                assoc = meta.assets[:assoc]
                if model && assoc
                    if source_actions = model_actions[model.name.to_sym]
                        source_action = source_actions.select{|sa| sa.meta_proc && sa.*.class >= meta.class}
                        # source_action = source_actions.select{|sa| sa.meta_proc && meta.class <= sa.*.class}
                        unless source_action.empty?
                            # raise E2Error.new("Multiple meta candidates for #{action.inspect} found in '#{source_action.inspect}'") if source_action.size > 1
                            # puts "#{action.inspect} => #{source_action.inspect}\n"
                            meta.instance_eval(&source_action.first.meta_proc)
                        end
                    end
                end

                meta.instance_eval(&action.meta_proc) if action.meta_proc
                true
            end

            each_action do |action|
                action.*.post_run
                action.*.freeze_meta
                true
            end

            ::Kernel::puts "ACTIONS: #{Action.count}, Time: #{::Time.now - time}"
        end

        def p *args
            ::Kernel::p *args
        end
    end


    class ActionBundle
        def initialize action, action_names
            @action = action
            @action_names = action_names
        end

        def method_missing name, *args, &blk
            @action_names.each{|an| @action[an].__send__(name, *args, &blk)}
        end
    end
end