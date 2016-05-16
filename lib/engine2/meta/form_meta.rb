# coding: utf-8

module Engine2
    class FormMeta < Meta
    end

    class CreateMeta < FormMeta
        include MetaCreateSupport
    end

    class ModifyMeta < FormMeta
        include MetaModifySupport
    end
end
