# coding: utf-8

module Engine2

    class SaveAction < Action
        include ActionSaveSupport
    end

    class InsertAction < SaveAction
        include ActionInsertSupport
        action_type :approve
    end

    class UpdateAction < SaveAction
        include ActionUpdateSupport
        action_type :approve
    end

    class StarToManyFieldInsertAction < InsertAction
        self.validate_only = true
        action_type :star_to_many_field_approve
    end

    class StarToManyFieldUpdateAction < UpdateAction
        self.validate_only = true
        action_type :star_to_many_field_approve
    end

end
