# coding: utf-8

module Engine2
    class DeleteMetaBase < Meta

        def invoke_delete_db handler, ids
            begin
                self.class.invoke_delete_db assets[:model], ids
            rescue Sequel::NoExistingObject
                handler.halt_not_found LOCS[:no_entry]
            rescue Sequel::DestroyFailed => failure
                handler.halt_forbidden failure.error.to_s
            end
        end

        def self.invoke_delete_db model, ids
            model.db.transaction do
                ids.each do |id|
                    keys = Sequel::split_keys(id)
                    restrict = model.association_reflections.select do |name, rel|
                        case rel[:type]
                        when :one_to_many
                            !model.db[name].where(Hash[rel[:keys].zip(keys)]).empty?
                        when :many_to_many
                            !model.db[rel[:join_table]].where(Hash[rel[:left_keys].zip(keys)]).empty?
                        when :many_to_one
                        when :one_to_one
                        else
                            unsupported_association rel[:type]
                        end
                    end
                    raise Sequel::DestroyFailed.new("Blokujące relacje: #{restrict.map{|name, rel| name}.join(', ')}" ) unless restrict.empty?

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