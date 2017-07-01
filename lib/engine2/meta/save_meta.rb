# coding: utf-8

module Engine2

    class SaveAction < Action
        include ActionSaveSupport
    end

    class InsertAction < SaveAction
        include ActionInsertSupport
        meta_type :approve
    end

    class UpdateAction < SaveAction
        include ActionUpdateSupport
        meta_type :approve
    end

    class StarToManyFieldInsertAction < InsertAction
        self.validate_only = true
        meta_type :star_to_many_field_approve
    end

    class StarToManyFieldUpdateAction < UpdateAction
        self.validate_only = true
        meta_type :star_to_many_field_approve
    end

end
