# coding: utf-8

module Engine2
    class FormAction < Action
        include ActionQuerySupport
    end

    class CreateAction < FormAction
        include ActionCreateSupport
    end

    class ModifyAction < FormAction
        include ActionModifySupport
    end
end
