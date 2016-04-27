# coding: utf-8

module Engine2
    class Schemes
        CRUD ||= {create: true, view: true, modify: true, delete: true}.freeze # bulk_delete: true
        VIEW ||= {view: true}.freeze
        LINK ||= {star_to_many_link: true, view: true, star_to_many_unlink: true}.freeze # star_to_many_bulk_unlink: true

        attr_reader :builtin, :user
        def initialize
            @builtin = {}
            @user = {}
        end

        def define_scheme name, &blk
            schemes = Engine2::core_loading ? @builtin : @user
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
            define_action name, ViewMeta
        end

        define_scheme :create do |name = :create|
            define_action name, CreateMeta do
                define_action :save, InsertMeta
            end
        end

        define_scheme :modify do |name = :modify|
            define_action name, ModifyMeta do
                define_action :save, UpdateMeta
            end
        end

        define_scheme :delete do
            define_action :confirm_delete, ConfirmMeta do
                self.*.response message: LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_delete_title]
                define_action :delete, DeleteMeta
            end
        end

        define_scheme :bulk_delete do
            define_action :confirm_bulk_delete, ConfirmMeta do
                self.*.response message: LOCS[:delete_question]
                self.*.panel_title LOCS[:confirm_bulk_delete_title]
                define_action :bulk_delete, BulkDeleteMeta
            end
        end

        define_scheme :default do |name, model, options|
            options ||= Schemes::CRUD
            define_action name, ListMeta, model: model do
                options.each{|k, v| run_scheme(k) if v}

                define_action_bundle :form, :create, :modify if options[:create] && options[:modify]
                # define_action_bundle :decode, :decode_entry, :decode_list, :typahead

                # if ?
                define_action :decode_entry, DecodeEntryMeta
                define_action :decode_list, DecodeListMeta
                define_action :typeahead, TypeAheadMeta
            end
        end

        #
        # Many to One
        #
        define_scheme :many_to_one do
            define_action :list, ManyToOneListMeta do
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

            define_action :"#{assoc_name}!" do
                # iterate over options like in :default ?
                define_action :list, DecodeListMeta, assoc: assoc if options[:list]
                define_action :typeahead, TypeAheadMeta, assoc: assoc if options[:typeahead]
                define_action :decode, DecodeEntryMeta, assoc: assoc do
                    run_scheme :many_to_one
                end if options[:scaffold]
            end
        end

        #
        # * to Many
        #
        define_scheme :star_to_many_unlink do
            define_action :confirm_unlink, ConfirmMeta do
                self.*.response message: LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_unlink_title]
                define_action :unlink, StarToManyUnlinkMeta
            end
        end

        define_scheme :star_to_many_bulk_unlink do
            define_action :confirm_bulk_unlink, ConfirmMeta do
                self.*.response message: LOCS[:unlink_question]
                self.*.panel_title LOCS[:confirm_bulk_unlink_title]
                define_action :bulk_unlink, StarToManyBulkUnlinkMeta
            end
        end

        define_scheme :star_to_many_link do
            define_action :link_list, StarToManyLinkListMeta do
                run_scheme :view
                define_action :link, StarToManyLinkMeta
            end
        end

        define_scheme :star_to_many do |act, assoc, model|
            options = assoc[:options] || Schemes::LINK
            define_action act, StarToManyListMeta, model: model, assoc: assoc do
                options.each{|k, v| run_scheme(k) if v}

                define_action_bundle :form, :create, :modify if options[:create] && options[:modify]
            end
        end

        #
        # arbitrary files per form
        #
        define_scheme :file_store do |model, field|
            define_action :"#{field}_file_store!", FileStoreMeta do
                self.*.model = model
                self.*.field = field
                define_action :download, DownloadFileStoreMeta
                define_action :upload, UploadFileStoreMeta
            end
        end

        #
        # blob field in source table
        #
        define_scheme :blob_store do |model, field|
            define_action :"#{field}_blob_store!", BlobStoreMeta do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_action :download, DownloadBlobStoreMeta
                define_action :upload, UploadBlobStoreMeta
            end
        end

        #
        # blob field in foreign (one to one) table
        #
        define_scheme :foreign_blob_store do |model, field|
            define_action :"#{field}_blob_store!", ForeignBlobStoreMeta do
                self.*.model = model
                self.*.field = field # model.type_info[field][:field]
                define_action :download, DownloadForeignBlobStoreMeta
                define_action :upload, UploadBlobStoreMeta
            end
        end

        define_scheme :star_to_many_field do |assoc, field|
            define_action :"#{field}!", StarToManyFieldMeta, assoc: assoc do
                run_scheme :view
                define_action :confirm_unlink, ConfirmMeta do
                    self.*.response message: LOCS[:unlink_question]
                    define_action :unlink, StarToManyFieldUnlinkMeta
                end
                define_action :link_list, StarToManyFieldLinkListMeta do
                    run_scheme :view
                end
            end
        end

    end
end