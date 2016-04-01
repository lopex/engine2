# coding: utf-8

module Engine2
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
            super
            @values[:password] = nil
            errors.empty?
        end

        def to_hash
            {name: @values[:name]}
        end
    end
end