# coding: utf-8

module Engine2
    class UserInfo < Sequel::Model(DUMMYDB)
        set_natural_key :name
        extend MemoryModel

        type_info do
            string_field :name, 10
            required :name, LOCS[:user_required]
            string_field :password, 20
            required :password, LOCS[:password_required]
            password :password
        end

        def validate_record handler, record
            super
            @values[:password] = nil
        end

        def to_hash
            {name: @values[:name]}
        end
    end
end