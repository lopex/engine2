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

    class StarToManyFieldInsertMeta < InsertMeta
        self.validate_only = true
        meta_type :star_to_many_field_approve
    end

    class StarToManyFieldUpdateMeta < UpdateMeta
        self.validate_only = true
        meta_type :star_to_many_field_approve
    end

end
