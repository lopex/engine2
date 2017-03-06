# coding: utf-8

module Engine2
    class FormMeta < Meta
        include MetaQuerySupport
    end

    class CreateMeta < FormMeta
        include MetaCreateSupport
    end

    class ModifyMeta < FormMeta
        include MetaModifySupport
    end

    class StarToManyFieldModifyMeta < ModifyMeta
        meta_type :star_to_many_field_modify
    end
end
