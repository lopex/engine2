# coding: utf-8

module Engine2
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
end