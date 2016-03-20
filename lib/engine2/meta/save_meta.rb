# coding: utf-8

module Engine2
    class ApproveMeta < Meta
        attr_reader :validations

        include MetaModelSupport
        http_method :post

        # def pre_run
        #     super
        #     @validate_fields = assets[:model].type_info.keys
        # end

        def validate_fields *fields
            if fields.empty?
                @validate_fields
            else
                @validate_fields = assets[:model].type_info.keys & (fields + assets[:model].primary_keys).uniq
            end
        end

        def before_approve handler, record
        end

        def after_approve handler, record
        end

        def approve_record handler, record
            static.before_approve(handler, record)
            record.valid?
            validate_record(handler, record)
            if record.errors.empty?
                static.after_approve(handler, record)
                true
            else
                false
            end
        end

        def allocate_record handler
            json = handler.post_to_json
            model = assets[:model]

            json_rec = json[:record]
            handler.permit json_rec.is_a?(Hash)
            val_fields = (dynamic? ? static.validate_fields : @validate_fields) || model.type_info.keys
            handler.permit (json_rec.keys - val_fields).empty?

            record = model.call(json_rec)
            record.validate_fields = val_fields
            record
        end

        def record handler, record
            {errors: nil} # nil # fields ?
        end

        def invoke handler
            record = allocate_record(handler)
            if approve_record(handler, record)
                static.record(handler, record)
            else
                # errors = record.errors.inject({}) do |h, (k, v)|
                #     k.is_a?(Array) ? k.each{|e|h[e] = v} : h[k] = v
                #     h
                # end
                {record: record.to_hash, errors: record.errors}
            end
        end

        def validate name, &blk
            (@validations ||= {})[name] = blk
        end

        def validate_record handler, record
            @validations.each do |name, val|
                unless record.errors.include? name
                    result = val.(record)
                    record.errors.add(name, result)
                end
            end if @validations
        end

        def post_run
            super
            validate_fields *action.parent.*.get[:fields] unless validate_fields
        end
    end

    class SaveMeta < ApproveMeta
        # meta_type :save
        def save_record handler, record
            static.before_approve(handler, record)
            record.valid?
            validate_record(handler, record)
            if record.errors.empty?
                static.after_approve(handler, record)

                if record.save(transaction: false, validate: false)
                    true
                else
                    false
                end
            else
                false
            end

            rescue Sequel::NoExistingObject => error # doesnt throw anymore
                handler.halt_not_found LOCS[:no_entry]
        end

        def approve_record handler, record
            record.skip_save_refresh = true
            record.raise_on_save_failure = false

            model = assets[:model]
            model.validation_in_transaction ? model.db.transaction{save_record(handler, record)} : save_record(handler, record)
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
