#coding: utf-8

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

class Object
    def instance_variables_hash
        instance_variables.inject({}) do |h, i|
            h[i] = instance_variable_get(i)
            h
        end
    end
end

class Proc
    def to_json(*)
        loc = source_location
        "\"#<Proc:#{loc.first[/\w+.rb/]}:#{loc.last}>\""
    end

    def chain &blk
        proc = self
        lambda do |obj|
            obj.instance_eval(&proc)
            obj.instance_eval(&blk)
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

class String
    def limit_length num
        s = self.strip
        if s.length > num
            s[0..num] + "..."
        else
            s
        end
    end
end

class Symbol
    def icon
        "<span class='glyphicon glyphicon-#{self}'></span>"
    end

    def aicon
        "<i class='fa fa-#{self}'></i>"
    end
end

class << Sequel
    attr_accessor :alias_tables_in_joins

    def split_keys id
        id.split('|')
    end
end

class Sequel::Database
    attr_accessor :models, :default_schema

    def cache_file
        "#{APP_LOCATION}/#{opts[:orig_opts][:name]}.dump"
    end

    def load_schema_cache_from_file
        self.models = {}
        load_schema_cache? cache_file if adapter_scheme
    end

    def dump_schema_cache_to_file
        dump_schema_cache? cache_file if adapter_scheme
    end
end

Sequel.quote_identifiers = false
Sequel.extension :core_extensions
Sequel::Inflections.clear
Sequel.alias_tables_in_joins = true
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
                model.dummies.each do |d|
                    dummies[d] = values.delete(d)
                end
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
                value.strip! unless info[:dont_strip]
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
            primary_keys.map{|k|k.qualify(table_name)}
        end

        def primary_keys_hash id
            Hash[primary_keys.zip(id)]
        end

        def primary_keys_hash_qualified id
            Hash[primary_keys_qualified.zip(id)]
        end
    end

    module DatasetMethods

        def ensure_primary_key
            pk = @model.primary_keys
            raise Engine2::E2Error.new("No primary key defined for model #{model}") unless pk && pk.all?

            if opts_select = @opts[:select]
                sel_pk = []
                opts_select.each do |sel|
                    name = case sel
                        when Symbol
                            sel.to_s =~ /\w+__(\w+)/ ? $1.to_sym : sel
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
                    sels = (pk - sel_pk).map{|k| k.qualify(@model.table_name)}
                    select_more(*sels)
                end
            else
                select(*pk.map{|k| k.qualify(@model.table_name)})
            end

        end

        def setup! fields
            joins = {}
            type_info = model.type_info
            model_table_name = model.table_name

            @opts[:select].map! do |sel|
                extract_select sel do |table, name, aliaz|
                    if table
                        if table == model_table_name
                            m = model
                        else
                            a = model.many_to_one_associations[table] # || model.one_to_one_associations[table]
                            raise Engine2::E2Error.new("Association #{table} not found for model #{model}") unless a
                            m = Object.const_get(a[:class_name])
                        end
                        # raise Engine2::E2Error.new("Model not found for table #{table} in model #{model}") unless m
                        info = m.type_info
                    else
                        info = type_info
                    end

                    f_info = info[name]
                    raise Engine2::E2Error.new("Column #{name} not found for table #{table || model_table_name}") unless f_info

                    table ||= model_table_name

                    if table == model_table_name
                        fields << name
                    else
                        fields << :"#{table}__#{name}"
                        joins[table] = model.many_to_one_associations[table]
                    end

                    if f_info[:dummy]
                        nil
                    # elsif f_info[:type] == :blob_store
                    #     # (~{name => nil}).as :name
                    #     # Sequel.char_length(name).as name
                    #     nil
                    else
                        if table != model_table_name
                            if Sequel.alias_tables_in_joins
                                name.qualify(table).as(:"#{table}__#{name}")
                            else
                                name.qualify(table)
                            end
                        else
                            name.qualify(table)
                        end
                    end
                end
            end

            @opts[:select].compact!

            joins.reduce(self) do |joined, (table, assoc)|
                m = Object.const_get(assoc[:class_name])
                keys = assoc[:qualified_key]
                joined.left_join(table, m.primary_keys.zip(keys.is_a?(Array) ? keys : [keys]))
            end
        end

        def extract_select sel, al = nil, &blk
            case sel
            when Symbol
                if sel.to_s =~ /^(\w+)__(\w+?)(?:___(\w+))?$/
                    yield $1.to_sym, $2.to_sym, $3 ? $3.to_sym : nil
                else
                    yield nil, sel, al
                end
            when Sequel::SQL::QualifiedIdentifier
                yield sel.table, sel.column, al
            when Sequel::SQL::AliasedExpression
                sel
                # extract_select sel.expression, sel.aliaz, &blk
                # expr = sel.expression
                # yield  expr.table, expr.column
            else
                raise Engine2::E2Error.new("Unknown selection #{sel}")
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

    class << self
        attr_accessor :core_loaded

        def database name
            Object.const_set(name, yield) unless Object.const_defined?(name)
        end

        def connect *args
            db = Sequel.connect *args
            db.models = {}
            db
        end

        def boot &blk
            @boot_blk = blk
        end

        def model_boot &blk
            @model_boot_blk = blk
        end

        def bootstrap app = APP_LOCATION
            self.core_loaded = true
            require 'engine2/pre_bootstrap'
            t = Time.now
            Action.count = 0
            SCHEMES.user.clear

            Sequel::DATABASES.each do |db|
                db.models.each{|n, m| Object.send(:remove_const, n) if Object.const_defined?(n)} unless db == E2DB || db == DUMMYDB
            end

            load "#{app}/boot.rb"

            Sequel::DATABASES.each &:load_schema_cache_from_file
            @model_boot_blk.() if @model_boot_blk
            load 'engine2/models/Files.rb'
            load 'engine2/models/UserInfo.rb'
            Dir["#{app}/models/*"].each{|m| load m}
            puts "MODELS: #{Sequel::DATABASES.reduce(0){|s, d|s + d.models.size}}, Time: #{Time.now - t}"
            Sequel::DATABASES.each &:dump_schema_cache_to_file

            Engine2.send(:remove_const, :ROOT) if defined? ROOT
            Engine2.const_set(:ROOT, Action.new(nil, :api, DummyMeta, {}))

            @boot_blk.(ROOT)
            ROOT.setup_action_tree
            puts "BOOTSTRAP #{app}, Time: #{Time.new - t}"

            require 'engine2/post_bootstrap'
        end
    end

    e2_db_file = (defined? JRUBY_VERSION) ? "jdbc:sqlite:#{APP_LOCATION}/engine2.db" : "sqlite://#{APP_LOCATION}/engine2.db"
    E2DB ||= connect e2_db_file, loggers: [Logger.new($stdout)], convert_types: false, name: :engine2
    DUMMYDB ||= Sequel::Database.new uri: 'dummy'
    def DUMMYDB.synchronize *args;end

    self.core_loaded = false

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

        def option_index iname
            index = @entries.index{|e| (e.is_a?(MenuBuilder) ? e.name : e[:name]) == iname}
            raise E2Error.new("No menu option #{iname} found") unless index
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
end
