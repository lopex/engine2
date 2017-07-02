# coding: utf-8
# frozen_string_literal: true

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
            define_node name, ViewAction
        end

        define_scheme :create do |name = :create|
            define_node name, CreateAction do
                define_node :approve, InsertAction
            end
        end

        define_scheme :modify do |name = :modify|
            define_node name, ModifyAction do
                define_node :approve, UpdateAction
            end
        end

        define_scheme :delete do
            define_node :confirm_delete, ConfirmAction do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_delete_title]
                define_node :delete, DeleteAction
            end
        end

        define_scheme :bulk_delete do
            define_node :confirm_bulk_delete, ConfirmAction do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_bulk_delete_title]
                define_node :bulk_delete, BulkDeleteAction
            end
        end

        define_scheme :default do |name, model, options|
            options ||= Schemes::CRUD
            define_node name, ListAction, model: model do
                options.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :create, :modify if options[:create] && options[:modify]
                # define_node_bundle :decode, :decode_entry, :decode_list, :typahead

                # if ?
                define_node :decode_entry, DecodeEntryAction
                define_node :decode_list, DecodeListAction
                define_node :typeahead, TypeAheadAction
            end
        end

        #
        # Many to One
        #
        define_scheme :many_to_one do
            define_node :list, ManyToOneListAction do
                run_scheme :view
            end
        end

        define_scheme :decode do |model, assoc_name, options = {scaffold: true}|
            assoc = model.association_reflections[assoc_name]
            ::Kernel::raise E2Error.new("Association '#{assoc_name}' not found for model '#{model}'") unless assoc

            if self.*.assets[:model] != model && self.*.is_a?(ListAction)
                # verify relations ?
                mdl = assoc[:model]
                info = mdl.type_info[assoc[:keys].first]
                options = info[:decode][:search]
            end

            define_node :"#{assoc_name}!" do
                # iterate over options like in :default ?
                define_node :list, DecodeListAction, assoc: assoc if options[:list]
                define_node :typeahead, TypeAheadAction, assoc: assoc if options[:typeahead]
                define_node :decode, DecodeEntryAction, assoc: assoc do
                    run_scheme :many_to_one
                end if options[:scaffold]
            end
        end

        #
        # * to Many
        #
        define_scheme :star_to_many_unlink do
            define_node :confirm_unlink, ConfirmAction do
                self.*.message LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_unlink_title]
                define_node :unlink, StarToManyUnlinkAction
            end
        end

        define_scheme :star_to_many_bulk_unlink do
            define_node :confirm_bulk_unlink, ConfirmAction do
                self.*.message LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_bulk_unlink_title]
                define_node :bulk_unlink, StarToManyBulkUnlinkAction
            end
        end

        define_scheme :star_to_many_link do
            define_node :link_list, StarToManyLinkListAction do
                run_scheme :view
                define_node :link, StarToManyLinkAction
            end
        end

        define_scheme :star_to_many do |act, assoc, model|
            options = assoc[:options] || Schemes::LINK
            define_node act, StarToManyListAction, model: model, assoc: assoc do
                options.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :create, :modify if options[:create] && options[:modify]
            end
        end

        #
        # arbitrary files per form
        #
        define_scheme :file_store do |model, field|
            define_node :"#{field}_file_store!", FileStoreAction do
                self.*.model = model
                self.*.field = field
                define_node :download, DownloadFileStoreAction
                define_node :upload, UploadFileStoreAction
            end
        end

        #
        # blob field in source table
        #
        define_scheme :blob_store do |model, field|
            define_node :"#{field}_blob_store!", BlobStoreAction do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_node :download, DownloadBlobStoreAction
                define_node :upload, UploadBlobStoreAction
            end
        end

        #
        # blob field in foreign (one to one) table
        #
        define_scheme :foreign_blob_store do |model, field|
            define_node :"#{field}_blob_store!", ForeignBlobStoreAction do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_node :download, DownloadForeignBlobStoreAction
                define_node :upload, UploadBlobStoreAction
            end
        end

        define_scheme :star_to_many_field_view do
            define_node :view, ViewAction do
                action{@action_type = :star_to_many_field_view}
            end
        end

        define_scheme :star_to_many_field_link do
            define_node :link, StarToManyLinkAction
        end

        define_scheme :star_to_many_field_unlink do
            define_node :confirm_unlink, ConfirmAction do
                self.*.message LOCS[:unlink_question]
                define_node :unlink, StarToManyUnlinkAction do
                    action{@action_type = :star_to_many_field_unlink}
                end
            end
        end

        define_scheme :star_to_many_field_link_list do
            define_node :link_list, StarToManyFieldLinkListAction do
                run_scheme :view
            end
        end

        #
        # *_to_many_field
        #
        define_scheme :star_to_many_field do |assoc, field|
            schemes = assoc[:model].type_info.fetch(field)[:schemes]
            define_node :"#{field}!", StarToManyFieldAction, assoc: assoc do
                schemes.each{|k, v| run_scheme(k) if v}

                define_node_bundle :form, :star_to_many_field_create, :star_to_many_field_modify if schemes[:star_to_many_field_create] && schemes[:star_to_many_field_modify]
            end
        end

        define_scheme :star_to_many_field_create do
            define_node :create, CreateAction do
                define_node :approve, StarToManyFieldInsertAction
            end
        end

        define_scheme :star_to_many_field_modify do
            define_node :modify, ModifyAction do
                action{@action_type = :star_to_many_field_modify}
                define_node :approve, StarToManyFieldUpdateAction
            end
        end

        define_scheme :star_to_many_field_delete do
            define_node :confirm_delete, ConfirmAction do
                self.*.message LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_delete_title]
                define_node :delete, DeleteAction do
                    action{@action_type = :star_to_many_field_delete}
                end
            end
        end

        define_scheme :array do |name, model|
            define_node name, ArrayListAction, model: model do
            end
        end
    end
end