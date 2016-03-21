# coding: utf-8

module Engine2

    class SaveMeta < Meta
        include MetaApproveSupport
        http_method :post

        def validate_and_approve handler, record
            record.skip_save_refresh = true
            record.raise_on_save_failure = false
            model = assets[:model]
            save = lambda{|c| record.save(transaction: false, validate: false) if super(handler, record) }
            model.validation_in_transaction ? model.db.transaction(&save) : save.(nil)
        end
    end

    class InsertMeta < SaveMeta
        meta_type :save
        def allocate_record handler
            record = super(handler)
            record.instance_variable_set(:"@new", true)
            model = assets[:model]
            model.primary_keys.each{|k|record.values.delete k} unless model.natural_key
            handler.permit !record.has_primary_key? unless model.natural_key
            record
        end
    end

    class UpdateMeta < SaveMeta
        meta_type :save
        def allocate_record handler
            record = super(handler)
            model = assets[:model]
            handler.permit record.has_primary_key? unless model.natural_key
            record
        end
    end

    module TimeStampMeta
        def before_approve handler, record
            super
            puts "before approve"
        end

        def after_approve handler, record
            super
            puts "after approve"
        end
    end
end
