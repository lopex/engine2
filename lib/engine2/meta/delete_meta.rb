# coding: utf-8

module Engine2
    class DeleteMetaBase < Meta

        def invoke_delete_db handler, ids, from_assoc = nil
            begin
                self.class.invoke_delete_db assets[:model], ids, from_assoc
            rescue Sequel::NoExistingObject
                handler.halt_not_found LOCS[:no_entry]
            rescue Sequel::DestroyFailed => failure
                handler.halt_forbidden failure.error.to_s
            end
        end

        def self.raise_destroy_failed name
            raise Sequel::DestroyFailed.new("#{LOCS[:delete_restricted]}: #{name}" )
        end

        def self.invoke_delete_db model, ids, from_assoc = nil
            model.db.transaction do
                ids.each do |id|
                    keys = Sequel::split_keys(id)

                    model.association_reflections.each do |name, assoc|
                        ds = case assoc[:type]
                        when :one_to_one
                        when :one_to_many
                            model.db[name].where(Hash[assoc[:keys].zip(keys)])
                        when :many_to_many
                            model.db[assoc[:join_table]].where(Hash[assoc[:left_keys].zip(keys)])
                        when :many_to_one
                            nil
                        else
                            unsupported_association assoc[:type]
                        end

                        if assoc[:cascade] || from_assoc == assoc.associated_class.table_name
                            ds.delete
                        else
                            raise_destroy_failed(name) unless ds.empty?
                        end if ds
                    end

                    rec = model.call(Hash[model.primary_keys.zip(keys)])
                    rec.destroy(transaction: false)
                    # model.where(model.primary_keys_hash(keys)).delete # model.dataset[model.primary_key => id].delete
                end
            end
            {}
        end
    end

    class DeleteMeta < DeleteMetaBase
        include MetaDeleteSupport

        def invoke handler
            handler.permit id = handler.params[:id]
            invoke_delete_db(handler, [id])
        end
    end

    class StarToManyFieldDeleteMeta < DeleteMeta
        meta_type :star_to_many_field_delete
    end

    class BulkDeleteMeta < DeleteMetaBase
        include MetaBulkDeleteSupport

        def invoke handler
            ids = handler.param_to_json(:ids)
            handler.permit ids.is_a?(Array)
            invoke_delete_db(handler, ids)
        end
    end

end