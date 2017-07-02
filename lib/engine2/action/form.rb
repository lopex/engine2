# coding: utf-8
# frozen_string_literal: true

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
