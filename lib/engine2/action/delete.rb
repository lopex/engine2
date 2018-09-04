# coding: utf-8
# frozen_string_literal: true

module Engine2
    class DeleteActionBase < Action
        def invoke_delete_db handler, ids, from_assoc = nil
            model = assets[:model]
            model.db.transaction do
                ids.each do |id|
                    keys = split_keys(id)

                    model.association_reflections.each do |name, assoc|
                        ds = case assoc[:type]
                        when :one_to_one
                        when :one_to_many
                            model.db[assoc.associated_class.table_name].where(Hash[assoc[:keys].zip(keys)])
                        when :many_to_many
                            model.db[assoc[:join_table]].where(Hash[assoc[:left_keys].zip(keys)])
                        when :many_to_one
                            nil
                        else
                            unsupported_association assoc[:type]
                        end

                        if assoc[:delete] == :cascade || from_assoc == assoc.associated_class.table_name
                            ds.delete
                        else
                            raise Sequel::DestroyFailed.new("#{LOCS[:delete_restricted]}: #{name}") unless ds.empty?
                        end if ds
                    end

                    rec = model.call(Hash[model.primary_keys.zip(keys)])
                    rec.destroy(transaction: false)
                    # model.where(model.primary_keys_hash(keys)).delete # model.dataset[model.primary_key => id].delete
                end
            end

            rescue Sequel::NoExistingObject
                handler.halt_not_found LOCS[:no_entry]
            rescue Sequel::DestroyFailed => failure
                handler.halt_forbidden failure.error.to_s
            {}
        end
    end

    class DeleteAction < DeleteActionBase
        include ActionDeleteSupport

        def invoke handler
            handler.permit id = handler.params[:id]
            invoke_delete_db(handler, [id])
        end
    end

    class BulkDeleteAction < DeleteActionBase
        include ActionBulkDeleteSupport

        def invoke handler
            ids = handler.param_to_json(:ids)
            handler.permit ids.is_a?(Array)
            invoke_delete_db(handler, ids)
        end
    end

end