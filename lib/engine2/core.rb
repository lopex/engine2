# coding: utf-8
# frozen_string_literal: true

module PrettyJSON
    def to_json_pretty
        JSON.pretty_generate(self)
    end
end

class BigDecimal
    def to_json(*)
        # super
        to_s('f')
    end
end

class Sequel::SQL::QualifiedIdentifier
    def to_json(*)
        "\"#{table}__#{column}\""
    end

    def to_sym
        :"#{table}__#{column}"
    end
end

class Object
    def instance_variables_hash
        instance_variables.reduce({}) do |h, i|
            h[i] = instance_variable_get(i)
            h
        end
    end
end

class Proc
    def to_json(*)
        loc = source_location
        loc ? "\"#<Proc:#{loc.first[/\w+.rb/]}:#{loc.last}>\"" : '"source unknown"'
    end

    def chain &blk
        prc = self
        lambda do |obj|
            obj.instance_eval(&prc)
            obj.instance_eval(&blk)
        end
    end

    def chain_args &blk
        prc = self
        lambda do |*args|
            instance_exec(*args, &prc)
            instance_exec(*args, &blk)
        end
    end
end

class Hash
    include PrettyJSON

    def rmerge!(other_hash)
        merge!(other_hash) do |key, oldval, newval|
            oldval.class == self.class ? oldval.rmerge!(newval) : newval
        end
    end

    def rmerge(other_hash)
        r = {}
        merge(other_hash) do |key, oldval, newval|
            r[key] = oldval.class == self.class ? oldval.rmerge(newval) : newval
        end
    end

    def rmerge2(other_hash)
        r = {}
        merge(other_hash) do |key, oldval, newval|
            r[key] = oldval.class == self.class ? oldval.rmerge2(newval) : (oldval == nil ? newval : oldval)
        end
    end

    def rmerge2!(other_hash)
        r = {}
        merge!(other_hash) do |key, oldval, newval|
            r[key] = oldval.class == self.class ? oldval.rmerge2!(newval) : (oldval == nil ? newval : oldval)
        end
    end

    def rdup
        duplicate = self.dup
        duplicate.each_pair do |k,v|
            tv = duplicate[k]
            duplicate[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? tv.rdup : v
        end
        duplicate
    end

    def path *a
        h = self
        i = 0
        while h && i != a.length
            h = h[a[i]]
            i += 1
        end
        h
    end

    def path! *a, v
        h = self
        i = 0
        while i < a.length - 1
            h = h[a[i]] ||= {}
            i += 1
        end
        h[a[i]] = v
    end

end

class Array
    include PrettyJSON
end

class String
    def limit_length num
        s = self.strip
        if s.length > num
            s[0..num] + "..."
        else
            s
        end
    end

    def escape_html
        Rack::Utils.escape_html(self)
    end
end

class Symbol
    def icon extra_class = ''
        s = self.to_s
        if s[0, 3] == 'fa_'
            "<i class='fa fa-#{s[3 .. -1]} #{extra_class}'></i>"
        elsif idx = s.index('.')
            "<img src='#{s}'></img>"
        else
            "<span class='glyphicon glyphicon-#{s} #{extra_class}'></span>"
        end
    end

    def loc
        Engine2::LOCS[self]
    end

    def q col
        col.qualify self
    end

    def html body = '', attrs = {}
        element = self.to_s
        attrs = attrs.map{|k, v| "#{k}=\"#{v}\""}.join(" ")
        "<#{element} #{attrs}>#{body}</#{element}>"
    end
end

module Faye
    class WebSocket
        module API
            def send! msg
                msg = msg.to_json if msg.is_a? Hash
                send msg
            end
        end
    end
end

class << Sequel
    attr_accessor :alias_columns_in_joins
end

class Sequel::Database
    attr_accessor :models, :default_schema

    def cache_file
        "#{Engine2::SETTINGS.path_for(:db_path)}/#{opts[:orig_opts][:name]}.schema_cache"
    end

    def load_schema_cache_from_file
        self.models = {}
        load_schema_cache? cache_file if adapter_scheme
    end

    def dump_schema_cache_to_file
        dump_schema_cache? cache_file if adapter_scheme
    end
end

Sequel.extension :core_extensions
Sequel::Inflections.clear
Sequel.alias_columns_in_joins = true
# Sequel::Model.plugin :json_serializer, :naked => true
# Sequel::Model.plugin :timestamps
# Sequel::Model.plugin :validation_class_methods
# Sequel::Model.raise_on_typecast_failure = false
# Sequel::Model.raise_on_save_failure = false
# Sequel::Model.unrestrict_primary_key
# Sequel::Model.plugin :validation_helpers
Sequel::Database::extension :schema_caching

module E2Model
    module InstanceMethods
        attr_accessor :skip_save_refresh, :validate_fields

        def key? key
            @values.key? key
        end

        def has_primary_key?
            pk = self.pk
            pk.is_a?(Array) ? !pk.all?{|k|k.nil?} : !pk.nil?
        end

        def primary_key_values
            model.primary_keys.map{|k|@values[k]}
        end

        def _save_refresh
            super unless skip_save_refresh
        end

        def validation
        end

        def before_save
            super
            model.before_save_processors.each_pair do |name, proc|
                proc.(self, name, model.type_info.fetch(name))
            end if model.before_save_processors

            unless model.dummies.empty?
                dummies = {}
                json_fields = {}
                model.dummies.each do |d|
                    dummies[d] = values.delete(d)
                    info = model.type_info[d]
                    if info[:json_op] && val = dummies[d] # values[info[:field]] = info[:field].pg_jsonb.set("{#{info[:path].join(',')}}", val.to_json, true)
                        json = json_fields[info[:field]] ||= {}
                        info[:path].reduce(h = {}){|h, v|h[v] = {}}[info[:last]] = val
                        json.rmerge! h
                    end

                end

                json_fields.each{|f, j| values[f] = f.concat(j.to_json)}
                @dummy_fields = dummies
            end

            unless self.pk
                sequence = model.type_info[model.primary_key][:sequence]
                self[model.primary_key] = sequence.lit if sequence
            end
        end

        def after_save
            unless model.dummies.empty?
                @values.merge!(@dummy_fields)
                @dummy_fields = nil
            end
            model.after_save_processors.each_pair do |name, proc|
                proc.(self, name, model.type_info.fetch(name))
            end if model.after_save_processors

            super
        end

        def before_destroy
            model.before_destroy_processors.each_pair do |name, proc|
                proc.(self, name, model.type_info.fetch(name))
            end if model.before_destroy_processors
            super
        end

        def after_destroy
            model.after_destroy_processors.each_pair do |name, proc|
                proc.(self, name, model.type_info.fetch(name))
            end if model.after_destroy_processors
            super
        end

        def validate
            super
            auto_validate
            validation
        end

        def auto_validate
            type_info = model.type_info
            @validate_fields.each do |name| # || type_info.keys
                info = type_info[name]
                next if info[:primary_key] && !model.natural_key

                value = values[name].to_s
                value.strip! unless value.frozen? || info[:dont_strip]
                if value.empty?
                    if req = info[:required]
                        errors.add(name, req[:message]) if !req[:if] || req[:if].(self)
                    end
                else
                    info[:validations].each_pair do |validation, args|
                        validation_proc = Engine2::Validations[validation] || args[:lambda] # swap ?
                        raise E2Error.new("Validation not found for field '#{name}' of type #{validation}") unless validation_proc
                        if result = validation_proc.(self, name, info)
                            errors.add(name, result)
                            break
                        end
                    end
                end
            end

            # if errors.empty? && model.natural_key && new?
            #     unless model.dataset.where(model.primary_keys_hash(primary_key_values)).empty? # optimize the keys part
            #         model.primary_keys.each{|pk| errors.add(pk, "must be unique")}
            #     end
            # end
        end
    end

    module ClassMethods
        attr_reader :natural_key

        def set_natural_key key
            set_primary_key key
            @natural_key = true
        end

        def primary_keys
            # cache it ?
            key = primary_key
            key.is_a?(Array) ? key : [key]
        end

        def primary_keys_qualified
            # cache it ?
            primary_keys.map{|k|table_name.q(k)}
        end

        def primary_keys_hash id
            Hash[primary_keys.zip(id)]
        end

        def primary_keys_hash_qualified id
            Hash[primary_keys_qualified.zip(id)]
        end
    end

    module DatasetMethods
        def load *args
            if entry = self[*args]
                model.after_load_processors.each do |name, proc|
                    type_info = model.find_type_info(name)
                    name_sym = name.to_sym
                    proc.(entry, name_sym, type_info) if entry.key?(name_sym)
                end if model.after_load_processors
                entry
            end
        end

        def load_all
            entries = self.all
            apply_after_load_processors(model, entries) if model.after_load_processors
            entries
        end

        def apply_after_load_processors model, entries
            model.after_load_processors.each do |name, proc|
                type_info = model.find_type_info(name)
                name_sym = name.to_sym
                entries.each do |entry|
                    proc.(entry, name_sym, type_info) if entry.key?(name_sym)
                end
            end
        end

        def ensure_primary_key
            pk = model.primary_keys
            raise Engine2::E2Error.new("No primary key defined for model #{model}") unless pk && pk.all?

            if opts_select = @opts[:select]
                sel_pk = []
                opts_select.each do |sel|
                    name = case sel
                        when Symbol
                            sel
                        when Sequel::SQL::QualifiedIdentifier
                            sel.column
                        when Sequel::SQL::AliasedExpression
                            sel
                            # nil #sel.aliaz # ?
                            # sel.expression
                        end
                    sel_pk << name if name && pk.include?(name)
                end

                if pk.length == sel_pk.length
                    self
                else
                    sels = (pk - sel_pk).map{|k| model.table_name.q(k)}
                    select_more(*sels)
                end
            else
                select(*pk.map{|k| model.table_name.q(k)})
            end
        end

        def extract_select sel, al = nil, &blk
            case sel
            when Symbol
                yield nil, sel, nil
            when Sequel::SQL::QualifiedIdentifier
                yield sel.table, sel.column, al
            when Sequel::SQL::AliasedExpression, Sequel::SQL::Function
                sel
                # extract_select sel.expression, sel.aliaz, &blk
                # expr = sel.expression
                # yield  expr.table, expr.column
            else
                raise Engine2::E2Error.new("Unknown selection #{sel}")
            end
        end

        def setup_query fields
            joins = {}
            model_table_name = model.table_name

            select = @opts[:select].map do |sel|
                extract_select sel do |table, name, aliaz|
                    mdl = if table
                        if table == model_table_name
                            model
                        else
                            assoc = model.many_to_one_associations[table] || model.many_to_many_associations[table]
                            raise Engine2::E2Error.new("Association #{table} not found for model #{model}") unless assoc
                            assoc.associated_class
                        end
                    else
                        model
                    end

                    mdl_table_name = mdl.table_name
                    table ||= mdl_table_name
                    if mdl_table_name == model_table_name
                        fields << name
                    else
                        fields << table.q(name)
                        joins[mdl_table_name] ||= model.many_to_one_associations[table] || model.many_to_many_associations[table]
                    end

                    f_info = mdl.type_info[name]
                    raise Engine2::E2Error.new("Column #{name} not found for table #{table}") unless f_info
                    if f_info[:dummy]
                        f_info[:qualified_json_op] ? f_info[:qualified_json_op].as(name) : nil
                    else
                        qname = mdl_table_name.q(name)
                        if table == model_table_name
                            qname
                        else
                            Sequel.alias_columns_in_joins ? qname.as(:"#{table}__#{name}") : qname
                        end
                    end
                end
            end.compact

            joins.reduce(clone(select: select)) do |joined, (table, assoc)|
                m = assoc.associated_class
                case assoc[:type]
                when :many_to_one
                    keys = assoc[:qualified_key]
                    joined.left_join(table, m.primary_keys.zip(keys.is_a?(Array) ? keys : [keys]))
                when :many_to_many
                    joined.left_join(assoc[:join_table], assoc[:left_keys].zip(model.primary_keys)).left_join(m.table_name, m.primary_keys.zip(assoc[:right_keys]))
                else unsupported_association
                end
            end
        end

        def get_opts
            @opts
        end

        def with_proc &blk
            ds = clone
            ds.row_proc = blk
            ds
        end
    end
end

Sequel::Model.plugin E2Model

module Sequel
    class DestroyFailed < Error
        attr_reader :error

        def initialize error
            @error = error
        end
    end
end

module Engine2
    LOCS ||= Hash.new{|h, k| ":#{k}:"}
    PATH ||= File.expand_path('../..', File.dirname(__FILE__))
    SETTINGS ||= {
        key_separator: '|',
        app_path: 'app',
        db_path: 'db',
        model_path: 'models',
        view_path: 'views',
        asset_path: 'assets',
        conf_path: 'conf',
        log_path: 'log'
    }

    def SETTINGS.path_for path
        "#{self[:app_path]}/#{self[path]}"
    end unless SETTINGS.frozen?

    class << self
        attr_reader :core_loaded

        def database name
            Object.const_set(name, yield) unless Object.const_defined?(name)
        end

        def connect *args
            db = Sequel.connect *args
            db
        end

        def boot &blk
            @boot_blk = blk
        end

        def model_boot &blk
            @model_boot_blk = blk
        end

        def bootstrap_e2db
            e2_db_path = "#{Engine2::SETTINGS.path_for(:db_path)}/engine2.db"
            e2_db_url = (defined? JRUBY_VERSION) ? "jdbc:sqlite:#{e2_db_path}" : "sqlite://#{e2_db_path}"
            const_set :E2DB, connect(e2_db_url, loggers: [Logger.new($stdout)], convert_types: false, name: :engine2)
            const_set :DUMMYDB, Sequel::Database.new(uri: 'dummy')
            def DUMMYDB.synchronize *args;end
        end

        def reload
            @core_loaded = true
            t = Time.now
            ActionNode.count = 0
            SCHEMES.user.clear

            Sequel::DATABASES.each do |db|
                db.models.each{|n, m| Object.send(:remove_const, n) if Object.const_defined?(n)} unless db == E2DB || db == DUMMYDB
            end

            load "#{Engine2::SETTINGS[:app_path]}/boot.rb"

            Sequel::DATABASES.each &:load_schema_cache_from_file
            load 'engine2/models/Files.rb'
            load 'engine2/models/UserInfo.rb'
            Dir["#{Engine2::SETTINGS.path_for(:model_path)}/*.rb"].each{|m| load m}
            @model_boot_blk.() if @model_boot_blk
            puts "MODELS: #{Sequel::DATABASES.reduce(0){|s, d|s + d.models.size}}, Time: #{Time.now - t}"
            Sequel::DATABASES.each do |db|
                db.dump_schema_cache_to_file
                db.models.each{|n, m|m.synchronize_type_info}
            end

            send(:remove_const, :ROOT) if defined? ROOT
            const_set(:ROOT, ActionNode.new(nil, :api, RootAction, {}))

            @boot_blk.(ROOT)
            ROOT.setup_node_tree
            puts "BOOTSTRAP #{Engine2::SETTINGS[:name]}, Time: #{Time.new - t}"
        end

        def bootstrap path, settings = {}
            SETTINGS.merge! settings
            SETTINGS[:path] = path
            SETTINGS[:name] ||= File::basename(path)
            SETTINGS.freeze
            Handler.set :public_folder, "public"
            Handler.set :views, [SETTINGS.path_for(:view_path), "#{Engine2::PATH}/views"]
            bootstrap_e2db
            IdEncoder.instance = IdEncoder.new
            IdEncoder.key_separator = SETTINGS[:key_separator]

            require 'engine2/pre_bootstrap'
            reload
            require 'engine2/post_bootstrap'
        end
    end

    @core_loaded = false

    class E2Error < RuntimeError
        def initialize msg
            super
        end
    end

    class MenuBuilder
        attr_accessor :name
        attr_reader :entries

        def initialize name, properties = {}
            @name = name
            @properties = properties
            @entries = []
        end

        def properties props = nil
            props ? @properties.merge!(props) : @properties
        end

        def option name, properties = {}, index = @entries.size, &blk
            if blk
                entries = MenuBuilder.new(name, properties)
                entries.instance_eval(&blk)
                @entries.insert index, entries
            else
                @entries.insert index, {name: name}.merge(properties)
            end
        end

        def option_before iname, name, properties = {}, &blk
            option name, properties, option_index(iname), &blk
        end

        def option_after iname, name, properties = {}, &blk
            option name, properties, option_index(iname) + 1, &blk
        end

        def option_at index, name, properties = {}, &blk
            option name, properties, index, &blk
        end

        def option_index iname, raise = true
            index = @entries.index{|e| (e.is_a?(MenuBuilder) ? e.name : e[:name]) == iname}
            raise E2Error.new("No menu option #{iname} found") if !index && raise
            index
        end

        def modify_option name, properties
            index = option_index(name)
            entry = @entries[index]
            props = entry.is_a?(MenuBuilder) ? entry.properties : entry
            props.merge!(properties)
        end

        def divider
            @entries << {divider: true}
        end

        def to_a
            @entries.map do |m|
                if m.is_a? MenuBuilder
                    h = {entries: m.to_a}.merge(m.properties)
                    h[:loc] ||= LOCS[m.name]
                    {menu: h}
                else
                    m[:loc] ? m : m.merge(loc: LOCS[m[:name]])
                end
            end
        end

        def each &blk
            @entries.each do |m|
                if m.is_a? MenuBuilder
                    m.each &blk
                else
                    yield m
                end
            end
        end
    end

    class ActionMenuBuilder < MenuBuilder
        def option name, properties = {}, index = @entries.size, &blk
            super
        end
    end

    class IdEncoder
        class << self
            attr_accessor :instance, :key_separator

            def join_keys keys
                @instance.encode_id(keys).join(@key_separator)
            end

            def split_keys id
                @instance.decode_id(id.split(@key_separator))
            end
        end

        def initialize *args
        end

        def encode_id ids
            ids
        end

        def decode_id ids
            ids
        end

        def decode_ids ids, model
            ids
        end

        def encode_entry entry, model
        end

        def decode_entry entry, model
        end

        def encode_list list, model
        end

        def decode_associations entry, model
        end
    end

    class AIdEncoder < IdEncoder
        def initialize *args
            super
        end

        def encode_id ids
            ids.map{|id| encode!(id)} # TODO: specialize
        end

        def decode_id ids
            ids.map{|id| decode!(id)} # TODO: specialize
        end

        def decode_ids ids, model
            ids.map{|id| id.map{|idi| decode!(idi)}}
        end

        def encode_entry entry, model
            model.primary_keys.each do |key|
                value = entry[key]
                entry[key] = encode!(value) if value && is_integer?(model, key)
            end
            encode_associations(entry, model)
        end

        def decode_entry entry, model
            model.primary_keys.each do |key|
                value = entry[key]
                entry[key] = decode!(value) if value && is_integer?(model, key)
            end
            decode_associations(entry, model)
        end

        def encode_list list, model
            list.each do |entry|
                encode_entry(entry, model)
            end
        end

        def encode_associations entry, model
            model.many_to_one_associations.each do |name, assoc|
                assoc[:keys].each do |key|
                    value = entry[key]
                    entry[key] = encode!(value) if value && is_integer?(model, key)
                end
            end
        end

        def decode_associations entry, model
            # TODO: handle cases like: model__assoc_id in search
            model.many_to_one_associations.each do |name, assoc|
                assoc[:keys].each do |key|
                    value = entry[key]
                    entry[key] = decode!(value) if value && is_integer?(model, key)
                end
            end
        end

        private

        def is_integer? model, key
            model.type_info[key][:otype] == :integer
        end
    end

    class HashIdEncoder < AIdEncoder
        attr_accessor :hashids

        def initialize *args
            super
            @hashids = Hashids.new *args
        end

        private

        def encode! id
            @hashids.encode(id)
        end

        def decode! id
            @hashids.decode(id).first
        end
    end

    class RandomHashIdEncoder < HashIdEncoder
        def initialize *args
            super
        end
    end

end
