# coding: utf-8

module Engine2

    class SaveMeta < Meta
        include MetaApproveSupport

        def validate_and_approve handler, record, json
            record.skip_save_refresh = true
            record.raise_on_save_failure = false
            model = assets[:model]
            assoc = assets[:assoc]
            mtm_insert = record.new? && assoc && assoc[:type] == :many_to_many

            parent_id = json[:parent_id]
            save = lambda do|c|
                if super(handler, record, json)
                    result = record.save(transaction: false, validate: false)
                    if result && mtm_insert
                        handler.permit parent_id
                        model.db[assoc[:join_table]].insert(assoc[:left_keys] + assoc[:right_keys], split_keys(parent_id) + record.primary_key_values)
                    end
                    result
                end
            end
            (model.validation_in_transaction || mtm_insert) ? model.db.transaction(&save) : save.(nil)
        end
    end

    class InsertMeta < SaveMeta
        meta_type :approve
        def allocate_record handler, json
            record = super(handler, json)
            record.instance_variable_set(:"@new", true)
            model = assets[:model]
            model.primary_keys.each{|k|record.values.delete k} unless model.natural_key
            handler.permit !record.has_primary_key? unless model.natural_key
            record
        end
    end

    class UpdateMeta < SaveMeta
        meta_type :approve
        def allocate_record handler, json
            record = super(handler, json)
            model = assets[:model]
            handler.permit record.has_primary_key? unless model.natural_key
            record
        end
    end
end
