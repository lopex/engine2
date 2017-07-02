# coding: utf-8
# frozen_string_literal: true

module Engine2

    class ActionNode < BasicObject
        ACCESS_FORBIDDEN ||= ->h{false}
        attr_reader :parent, :name, :number, :nodes, :recheck_access
        attr_reader :meta_proc, :access_block

        class << self
            attr_accessor :count
        end

        def initialize parent, name, action_class, assets
            ActionNode.count += 1
            @number = ActionNode.count
            @parent = parent
            @name = name
            @action = action_class.new(self, assets)
            @nodes = {}
        end

        def * &blk
            @meta_proc = @meta_proc ? @meta_proc.chain(&blk) : blk if blk
            @action
        end

        alias :action :*

        def access! &blk
            ::Kernel.raise E2Error.new("Access for node #{name} already defined") if @access_block
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

        def define_node name, action_class = InlineAction.inherit, assets = {}, &blk
            ::Kernel.raise E2Error.new("ActionNode #{name} already defined") if @nodes[name]
            node = @nodes[name] = ActionNode.new(self, name, action_class, assets)
            node.*.pre_run
            define_singleton_method! name do |&ablk| # forbidden list
                node.instance_eval(&ablk) if ablk
                node
            end
            node.instance_eval(&blk) if blk
            node.*.node_defined
            node
        end

        def define_action name, action_class = InlineAction.inherit, assets = {}, &blk
            define_node name, action_class, assets do
                self.* &blk
            end
        end

        def define_invoke name, action_class = InlineAction.inherit, assets = {}, &blk
            define_node name, action_class, assets do
                self.*.define_invoke &blk
            end
        end

        def define_node_bundle name, *nodes
            define_singleton_method!(name) do |&blk|
                if blk
                    nodes.each{|a|__send__(a, &blk)} # if @nodes[node] ?
                else
                    ActionNodeBundle.new(self, nodes)
                end
            end
        end

        def define_singleton_method! name, &blk
            class << self;self;end.instance_eval do # __realclass__
                define_method name, &blk
            end
        end

        def [] name
            @nodes[name]
        end

        def nodes_info handler
            info = nodes.reduce({}) do |h, (name, a)|
                action = a.*
                act = {
                    action_type: action.action_type,
                    method: action.http_method,
                    number: a.number,
                    terminal: a.nodes.empty?,
                    meta: !action.meta.empty?
                }

                act[:access] = true if !recheck_access && a.check_access!(handler)
                act[:recheck_access] = true if a.recheck_access

                if Handler::development?
                    act[:action_class] = action.class
                    act[:access_block] = a.access_block if a.access_block
                    act[:model] = action.assets[:model]
                end

                h[name] = act
                h
            end

            info.first[1][:default] = true unless nodes.empty?
            info
        end

        def access_info handler
            @nodes.reduce({}) do |h, (name, a)|
                h[name] = a.check_access!(handler)
                h
            end
        end

        def recheck_access!
            @recheck_access = true
        end

        def each_node &blk
            # no self
            @nodes.each_pair do |n, a|
                a.each_node(&blk) if yield a
            end
        end

        def to_a_rec root = true, result = [], &blk # optimize
            if root && (yield self)
                result << self
                @nodes.each_pair do |n, a|
                    if yield a
                        result << a
                        a.to_a_rec(false, result, &blk)
                    end
                end
            end
            result
        end

        def inspect
            "ActionNode: #{@name}, action: #{@action.class}, action_type: #{@action.action_type}"
        end

        def setup_node_tree
            time = ::Time.now

            model_nodes = {}
            each_node do |node|
                if model = node.*.assets[:model]
                    model_name = model.name.to_sym
                    model.synchronize_type_info
                    model_nodes[model_name] = node.to_a_rec{|a| !a.*.assets[:assoc]}
                    node.run_scheme(model_name) if SCHEMES[model_name, false]
                    false
                else
                    true
                end
            end

            thefts = 0
            each_node do |node|
                action = node.*
                model = action.assets[:model]
                assoc = action.assets[:assoc]
                if model && assoc
                    if source_nodes = model_nodes[model.name.to_sym]
                        source_node = source_nodes.select{|sa| sa.meta_proc && sa.*.class >= action.class}
                        # source_node = source_nodes.select{|sa| sa.meta_proc && action.class <= sa.*.class}
                        unless source_node.empty?
                            raise E2Error.new("Multiple action candidates for #{node.inspect} found in '#{source_node.inspect}'") if source_node.size > 1
                            # puts "#{node.inspect} => #{source_node.inspect}\n"
                            action.instance_eval(&source_node.first.meta_proc)
                            thefts += 1
                        end
                    end
                end

                action.instance_eval(&node.meta_proc) if node.meta_proc
                true
            end

            each_node do |node|
                node.*.post_run
                node.*.freeze_meta
                true
            end

            ::Kernel::puts "ACTION NODES: #{ActionNode.count}, Time: #{::Time.now - time}, Thefts: #{thefts}"
        end

        def p *args
            ::Kernel::p *args
        end
    end


    class ActionNodeBundle
        def initialize node, node_names
            @node = node
            @node_names = node_names
        end

        def method_missing name, *args, &blk
            @node_names.each{|an| @node[an].__send__(name, *args, &blk)}
        end
    end
end