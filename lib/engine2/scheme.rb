# coding: utf-8

module Engine2
    class Schemes
        CRUD ||= {create: true, view: true, modify: true, delete: true}.freeze # bulk_delete: true
        VIEW ||= {view: true}.freeze
        LINK ||= {star_to_many_link: true, view: true, star_to_many_unlink: true}.freeze # star_to_many_bulk_unlink: true
        STMF_CRUD ||= {star_to_many_field_create: true, star_to_many_field_view: true, star_to_many_field_modify: true, star_to_many_field_delete: true}.freeze
        STMF_VIEW ||= {star_to_many_field_view: true}.freeze
        STMF_LINK ||= {star_to_many_field_view: true, star_to_many_field_link: true ,star_to_many_field_unlink: true, star_to_many_field_link_list: true}.freeze

        attr_reader :builtin, :user
        def initialize
            @builtin = {}
            @user = {}
        end

        def define_scheme name, &blk
            schemes = Engine2::core_loaded ? @user : @builtin
            raise E2Error.new("Scheme '#{name}' already defined") if schemes[name]
            schemes[name] = blk
        end

        def [] name, raise = true
            scheme = @builtin[name] || @user[name]
            raise E2Error.new("Scheme #{name} not found") if !scheme && raise
            scheme
        end
    end

    SCHEMES ||= Schemes.new
    SCHEMES.builtin.clear
    SCHEMES.instance_eval do

        define_scheme :view do |name = :view|
            define_node name, ViewMeta
        end

        define_scheme :create do |name = :create|
            define_node name, CreateMeta do
                define_node :approve, InsertMeta
            end
        end

        define_scheme :modify do |name = :modify|
            define_node name, ModifyMeta do
                define_node :approve, UpdateMeta
            end
        end

        define_scheme :delete do
            define_node :confirm_delete, ConfirmMeta do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_delete_title]
                define_node :delete, DeleteMeta
            end
        end

        define_scheme :bulk_delete do
            define_node :confirm_bulk_delete, ConfirmMeta do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_bulk_delete_title]
                define_node :bulk_delete, BulkDeleteMeta
            end
        end

        define_scheme :default do |name, model, options|
            options ||= Schemes::CRUD
            define_node name, ListMeta, model: model do
                options.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :create, :modify if options[:create] && options[:modify]
                # define_node_bundle :decode, :decode_entry, :decode_list, :typahead

                # if ?
                define_node :decode_entry, DecodeEntryMeta
                define_node :decode_list, DecodeListMeta
                define_node :typeahead, TypeAheadMeta
            end
        end

        #
        # Many to One
        #
        define_scheme :many_to_one do
            define_node :list, ManyToOneListMeta do
                run_scheme :view
            end
        end

        define_scheme :decode do |model, assoc_name, options = {scaffold: true}|
            assoc = model.association_reflections[assoc_name]
            ::Kernel::raise E2Error.new("Association '#{assoc_name}' not found for model '#{model}'") unless assoc

            if self.*.assets[:model] != model && self.*.is_a?(ListMeta)
                # verify relations ?
                mdl = assoc[:model]
                info = mdl.type_info[assoc[:keys].first]
                options = info[:decode][:search]
            end

            define_node :"#{assoc_name}!" do
                # iterate over options like in :default ?
                define_node :list, DecodeListMeta, assoc: assoc if options[:list]
                define_node :typeahead, TypeAheadMeta, assoc: assoc if options[:typeahead]
                define_node :decode, DecodeEntryMeta, assoc: assoc do
                    run_scheme :many_to_one
                end if options[:scaffold]
            end
        end

        #
        # * to Many
        #
        define_scheme :star_to_many_unlink do
            define_node :confirm_unlink, ConfirmMeta do
                self.*.message LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_unlink_title]
                define_node :unlink, StarToManyUnlinkMeta
            end
        end

        define_scheme :star_to_many_bulk_unlink do
            define_node :confirm_bulk_unlink, ConfirmMeta do
                self.*.message LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_bulk_unlink_title]
                define_node :bulk_unlink, StarToManyBulkUnlinkMeta
            end
        end

        define_scheme :star_to_many_link do
            define_node :link_list, StarToManyLinkListMeta do
                run_scheme :view
                define_node :link, StarToManyLinkMeta
            end
        end

        define_scheme :star_to_many do |act, assoc, model|
            options = assoc[:options] || Schemes::LINK
            define_node act, StarToManyListMeta, model: model, assoc: assoc do
                options.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :create, :modify if options[:create] && options[:modify]
            end
        end

        #
        # arbitrary files per form
        #
        define_scheme :file_store do |model, field|
            define_node :"#{field}_file_store!", FileStoreMeta do
                self.*.model = model
                self.*.field = field
                define_node :download, DownloadFileStoreMeta
                define_node :upload, UploadFileStoreMeta
            end
        end

        #
        # blob field in source table
        #
        define_scheme :blob_store do |model, field|
            define_node :"#{field}_blob_store!", BlobStoreMeta do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_node :download, DownloadBlobStoreMeta
                define_node :upload, UploadBlobStoreMeta
            end
        end

        #
        # blob field in foreign (one to one) table
        #
        define_scheme :foreign_blob_store do |model, field|
            define_node :"#{field}_blob_store!", ForeignBlobStoreMeta do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_node :download, DownloadForeignBlobStoreMeta
                define_node :upload, UploadBlobStoreMeta
            end
        end

        define_scheme :star_to_many_field_view do
            define_node :view, ViewMeta do
                meta{@meta_type = :star_to_many_field_view}
            end
        end

        define_scheme :star_to_many_field_link do
            define_node :link, StarToManyLinkMeta
        end

        define_scheme :star_to_many_field_unlink do
            define_node :confirm_unlink, ConfirmMeta do
                self.*.message LOCS[:unlink_question]
                define_node :unlink, StarToManyUnlinkMeta do
                    meta{@meta_type = :star_to_many_field_unlink}
                end
            end
        end

        define_scheme :star_to_many_field_link_list do
            define_node :link_list, StarToManyFieldLinkListMeta do
                run_scheme :view
            end
        end

        #
        # *_to_many_field
        #
        define_scheme :star_to_many_field do |assoc, field|
            schemes = assoc[:model].type_info.fetch(field)[:schemes]
            define_node :"#{field}!", StarToManyFieldMeta, assoc: assoc do
                schemes.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :star_to_many_field_create, :star_to_many_field_modify if schemes[:star_to_many_field_create] && schemes[:star_to_many_field_modify]
            end
        end

        define_scheme :star_to_many_field_create do
            define_node :create, CreateMeta do
                define_node :approve, StarToManyFieldInsertMeta
            end
        end

        define_scheme :star_to_many_field_modify do
            define_node :modify, ModifyMeta do
                meta{@meta_type = :star_to_many_field_modify}
                define_node :approve, StarToManyFieldUpdateMeta
            end
        end

        define_scheme :star_to_many_field_delete do
            define_node :confirm_delete, ConfirmMeta do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_delete_title]
                define_node :delete, DeleteMeta do
                    meta{@meta_type = :star_to_many_field_delete}
                end
            end
        end

        define_scheme :array do |name, model|
            define_node name, ArrayListMeta, model: model do
            end
        end
    end
end