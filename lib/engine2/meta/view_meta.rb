# coding: utf-8

module Engine2
    class ViewMeta < Meta
        include MetaViewSupport, MetaQuerySupport
    end

    class StarToManyFieldViewMeta < Meta
        include MetaViewSupport, MetaQuerySupport
        meta_type :star_to_many_field_view
    end
end
