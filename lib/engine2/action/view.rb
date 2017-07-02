# coding: utf-8
# frozen_string_literal: true

module Engine2
    class ViewAction < Action
        include ActionViewSupport, ActionQuerySupport
    end
end
