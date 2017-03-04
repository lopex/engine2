# coding: utf-8

module Engine2

    class SaveMeta < Meta
        include MetaSaveSupport
    end

    class InsertMeta < SaveMeta
        include MetaInsertSupport
        meta_type :approve
    end

    class UpdateMeta < SaveMeta
        include MetaUpdateSupport
        meta_type :approve
    end

    class StarToManyFieldSaveMeta < Meta
        include MetaApproveSupport
        # def validate_and_approve handler, record, json
        #     # {}
        # end
    end

    class StarToManyFieldInsertMeta < StarToManyFieldSaveMeta
        include MetaInsertSupport
        meta_type :star_to_many_field_approve
    end

    class StarToManyFieldUpdateMeta < StarToManyFieldSaveMeta
        include MetaUpdateSupport
        meta_type :star_to_many_field_approve
    end

end
