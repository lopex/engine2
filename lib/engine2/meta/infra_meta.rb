# coding: utf-8

module Engine2
    SCHEMES::define_scheme :login! do |user_info_model = UserInfo|
        define_node :login_form, LoginFormMeta, model: user_info_model do
            access!{|h|!h.logged_in?}
            define_node :login, LoginMeta
        end
    end

    SCHEMES::define_scheme :logout! do
        define_node :logout_form, LogoutFormMeta do
            access! &:logged_in?
            define_node :logout, LogoutMeta
        end
    end

    SCHEMES::define_scheme :infra! do |user_info_model = UserInfo|
        run_scheme :login!, user_info_model
        define_node :infra!, InfraMeta do
            run_scheme :login!, user_info_model
            run_scheme :logout!

            define_node :inspect_modal, InspectModalMeta do
                access! &:logged_in?
                define_node :inspect, WebSocketMeta.inherit do
                    self.* do
                        @meta_type = :inspect

                        ws_message do |msg, ws|
                            ws.send! number: msg[:number].to_i + 1
                        end
                    end

                    define_node_invoke :models do |handler|
                        {models: Sequel::DATABASES.map{|db| {name: db.uri, models: db.models.keys} }}
                    end

                    define_node_invoke :model_info do |handler|
                        db_name = handler.params[:db]
                        handler.permit db = Sequel::DATABASES.find{|d|d.uri == db_name || (d.uri && d.uri.start_with?(db_name))}
                        handler.permit model = db.models[handler.params[:model].to_sym]
                        {
                            model!: {
                                info: {
                                    name: model.to_s,
                                    table: model.table_name
                                },
                                assoc: model.association_reflections,
                                schema: model.db_schema,
                                type_info: model.type_info
                            }
                        }
                    end

                    define_node_invoke :environment do |handler|
                        {environment: handler.env}
                    end
                end
            end
        end
    end

    SCHEMES::define_scheme :menu! do
        define_node :menu!, MenuMeta do
        end
    end

    class FileStoreMeta < Meta
        meta_type :file_store

        attr_accessor :model, :field

        def invoke handler
            handler.permit owner = handler.params[:owner]
            {files: E2Files.db[:files].select(:id, :name, :mime, :uploaded).where(owner: owner, model: model.name.to_s, field: field.to_s).all}
        end
    end


    module BlobSupportMeta
        def serve_blob handler, entry, inf
            handler.permit entry
            handler.attachment entry[inf[:name_field]]
            handler.content_type (entry[inf[:mime_field]].to_s.empty? ? "application/octet-stream" : entry[inf[:mime_field]])
            entry[inf[:bytes_field]].getBinaryStream().to_io.read
        end
    end

    class DownloadFileStoreMeta < Meta
        meta_type :download

        def invoke handler
            handler.permit id = handler.params[:id]
            entry = E2Files.db[:files].select(:name, :mime)[id: id]
            handler.permit entry
            handler.attachment entry[:name]
            handler.content_type (entry[:mime].to_s.empty? ? "application/octet-stream" : entry[:mime])
            info = node.parent.*.model.type_info[node.parent.*.field]
            open("#{info[:store][:files]}/#{entry[:name]}_#{id}", 'rb'){|f|f.read}
        end
    end

    class UploadFileStoreMeta < Meta
        http_method :post
        meta_type :upload

        def invoke handler
            file = handler.params[:file]
            temp = file[:tempfile]
            temp.close
            rackname = File.basename(temp.path)
            info = node.parent.*.model.type_info[node.parent.*.field]
            File.rename(temp.path, "#{info[:store][:upload]}/#{rackname}")
            {rackname: rackname}
        end
    end

    class BlobStoreMeta < Meta
        meta_type :blob_store

        attr_accessor :model, :field

        def invoke handler
            handler.permit id = handler.params[:owner]
            inf = model.type_info[field]
            result = model.naked.select(inf[:name_field], Sequel.char_length(inf[:bytes_field]).as(:length)).where(model.primary_keys_hash(split_keys(id))).first
            handler.permit result
            {file_name: result[inf[:name_field]], blob_length: result[:length]}
        end
    end

    class DownloadBlobStoreMeta < Meta
        include BlobSupportMeta
        meta_type :download_blob

        def invoke handler
            model = node.parent.*.model
            inf = model.type_info[node.parent.*.field]
            handler.permit id = handler.params[:id]

            entry = model.naked.select(inf[:bytes_field], inf[:name_field], inf[:mime_field]).where(model.primary_keys_hash(split_keys(id))).first
            serve_blob(handler, entry, inf)
        end
    end

    class UploadBlobStoreMeta < Meta
        http_method :post
        meta_type :upload_blob

        def invoke handler
            file = handler.params[:file]
            temp = file[:tempfile]
            temp.close
            rackname = File.basename(temp.path)
            info = node.parent.*.model.type_info[node.parent.*.field]
            File.rename(temp.path, "#{info[:store][:upload]}/#{rackname}")
            {rackname: rackname}
        end
    end

    class ForeignBlobStoreMeta < Meta
        meta_type :blob_store

        attr_accessor :model, :field

        def invoke handler
            handler.permit id = handler.params[:owner]

            inf = model.type_info[field]
            assoc = model.association_reflections[inf[:assoc_name]]
            blob_model = assoc.associated_class

            rec = model.naked.select(assoc[:key]).where(model.primary_keys_hash(split_keys(id))).first
            handler.permit rec
            result = blob_model.naked.select(inf[:name_field], Sequel.char_length(inf[:bytes_field]).as(:length)).where(blob_model.primary_key => rec[assoc[:key]]).first

            # handler.permit result
            {file_name: result ? result[inf[:name_field]] : :empty, blob_length: result ? result[:length] : 0}
        end
    end

    class DownloadForeignBlobStoreMeta < Meta
        include BlobSupportMeta
        meta_type :download_blob

        def invoke handler
            model = node.parent.*.model
            inf = model.type_info[node.parent.*.field]
            assoc = model.association_reflections[inf[:assoc_name]]
            blob_model = assoc.associated_class
            handler.permit id = handler.params[:id]
            rec = model.naked.select(assoc[:key]).where(model.primary_keys_hash(split_keys(id))).first
            handler.permit rec

            entry = blob_model.naked.select(inf[:bytes_field], inf[:name_field], inf[:mime_field]).where(blob_model.primary_key => rec[assoc[:key]]).first
            serve_blob(handler, entry, inf)
        end
    end

    # class UploadForeignBlobStoreMeta < Meta
    #     http_method :post
    #     meta_type :upload_blob

    #     def invoke handler
    #         file = handler.params[:file]
    #         temp = file[:tempfile]
    #         temp.close
    #         rackname = File.basename(temp.path)
    #         File.rename(temp.path, "#{UPLOAD_DIR}/#{rackname}")
    #         {rackname: rackname}
    #     end
    # end

    class InfraMeta < Meta
        include MetaPanelSupport, MetaMenuSupport, MetaAPISupport
        meta_type :infra

        def pre_run
            super
            panel_panel_template false
            panel_template 'infra/index'
            loc! logged_on: LOCS[:logged_on]
            menu :menu do
                properties group_class: "btn-group-sm"
                option :inspect_modal, icon: :wrench, button_loc: false # , show: "action.logged_on"
            end
        end

        def invoke handler
            user = handler.user
            {user: user ? user.to_hash : nil}
        end

        def login_meta show_login_otion = 'false', &blk
            node.login_form.* &blk
            menu(:menu).modify_option :login_form, show: show_login_otion
            node.parent.login_form.* &blk
        end
    end

    class InspectModalMeta < Meta
        include MetaPanelSupport, MetaMenuSupport
        meta_type :inline

        def pre_run
            super
            modal_action
            panel_template 'infra/inspect'
            panel_title "#{:wrench.icon} Inspect"
            panel_class "modal-huge"
            panel[:backdrop] = true
            menu(:panel_menu).option :cancel, icon: "remove"
        end
    end

    class LoginFormMeta < Meta
        include MetaFormSupport
        meta_type :login_form

        def pre_run
            super
            panel_class 'modal-default'
            panel_title LOCS[:login_title]
            info! :name, loc: LOCS[:user_name]
            menu(:panel_menu).modify_option :approve, name: :login, icon: :"log-in"
            @meta[:fields] = [:name, :password]
            parent_meta = node.parent.*
            if parent_meta.is_a? MetaMenuSupport
                parent_meta.menu(:menu).option :login_form, icon: :"log-in", disabled: "action.action_pending()"
            end
        end

        def invoke handler
            {record: {}, new: true}
        end
    end

    class LoginMeta < Meta
        include MetaApproveSupport
        meta_type :login

        def validate_record handler, record
            super
            record.values[:password] = nil
        end

        def after_approve handler, record
            handler.session[:user] = record
        end

        def record handler, record
            {errors: nil, user!: handler.user.to_hash}
        end
    end

    class LogoutFormMeta < Meta
        include MetaPanelSupport, MetaMenuSupport
        meta_type :logout_form
        def pre_run
            super
            panel_template 'scaffold/message'
            panel_title LOCS[:logout_title]
            panel_class 'modal-default'
            @meta[:message] = LOCS[:logout_message]
            node.parent.*.menu(:menu).option :logout_form, icon: :"log-out" # , show: "action.logged_on"
            menu :panel_menu do
                option :logout, icon: "ok", loc: LOCS[:ok]
                option :cancel, icon: "remove"
            end
        end
    end

    class LogoutMeta < Meta
        meta_type :logout

        def invoke handler
            handler.session.clear
            # handler.session[:logged_in] = false
            {}
        end
    end
end
