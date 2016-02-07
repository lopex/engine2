# coding: utf-8

module Engine2
	E2DB ||= connect (defined? JRUBY_VERSION) ? "jdbc:sqlite:#{APP_LOCATION}/e2.db" : "sqlite://#{APP_LOCATION}/e2.db",
		loggers: [Logger.new($stdout)], convert_types: false, name: :e2
    DUMMYDB ||= Sequel::Database.new

    BUILTIN_DBS ||= Sequel::DATABASES.dup
    BUILTIN_DBS.each &:load_schema_cache_from_file

	E2DB.create_table :files do
	    primary_key :id
	    String :name, size: 100, null: false
	    String :mime, fixed: true, size: 40, null: false
	    String :owner, fixed: true, size: 20, null: false
	    String :model, fixed: true, size: 20, null: false
	    String :field, fixed: true, size: 20, null: false
	    DateTime :uploaded, null: false
	end unless E2DB.table_exists?(:files)

	class E2Files < Sequel::Model(E2DB[:files])
	    extend Engine2::Model

	    type_info do
	        # list_select :model, Hash[@model.db.models.keys.map{|m| [m, m]}]
	        # list_select :field, {}
	    end

	    scheme :default, Schemes::CRUD.merge(create: false, bulk_delete: true) do
	        self.* do
	            hide_pk
	            query select(:name, :mime, :owner, :model, :field, :uploaded)
	            sortable
	            searchable :name, :owner, :model, :field
	            search_live

		        on_change :model do |req, value|
		            # action.parent.*.assets[:model].select(:field).where(model: value).all.map{|rec|f = rec.values[:field]; [f, f]}
		            # render :field, list: {a: 1, b: 2}.to_a
		        end

	        end
	    end
	end

	BUILTIN_DBS.each &:dump_schema_cache_to_file

    # def define_dummy_model
    # end

    module MemoryModel
    	def self.extended cls
    		cls.extend Engine2::Model
    		cls.class_eval do
    			def save
    			end
    		end

	    	def cls.type_info &blk
	    		if blk
	    			super(&blk)
	    			@columns = @type_info.keys
	    			nil
	    		else
	    			@type_info
	    		end
	    	end

    	end
    end

    class UserInfo < Sequel::Model(DUMMYDB)
        extend MemoryModel
        set_natural_key :name

        type_info do
            string_field :name, 10
            required :name, LOCS[:user_required]
            string_field :password, 20
            required :password, LOCS[:password_required]
            password :password
        end

        def validate
        	auto_validate
        	@values[:password] = nil
        	errors.empty?
        end

        def to_hash
        	{name: @values[:name]}
        end
    end
end
