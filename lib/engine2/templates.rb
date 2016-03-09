# coding: utf-8

module Engine2
    BS_ANIMATION ||= "am-flip-x" # "am-fade"

    class Templates
        class << self
            def default_template
                {template: "fields/input_text"}
            end

            def text_area cols, rows
                {template: "fields/text_area", cols: cols, rows: rows}
            end

            def input_text length
                {template: "fields/input_text", length: length}
            end

            def text
                {template: "fields/text"}
            end

            def password length
                {template: "fields/password", length: length}
            end

            def file_store
                {template: "fields/file_store"}
            end

            def blob
                {template: "fields/blob"}
            end

            def integer
                {template: "fields/integer"}
            end

            def decimal
                {template: "fields/integer"}
            end

            def decimal_date
                {template: "fields/decimal_date", animation: BS_ANIMATION}
            end

            def decimal_time
                {template: "fields/decimal_time", animation: BS_ANIMATION}
            end

            def date_picker
                {template: "fields/date", animation: BS_ANIMATION}
            end

            def time_picker
                {template: "fields/time", animation: BS_ANIMATION}
            end

            def datetime_picker
                {template: "fields/datetime", animation: BS_ANIMATION}
            end

            def list_select length, options = {}
                options.merge({
                    template: options[:optional] ? "fields/list_select_opt" : "fields/list_select",
                    length: length
                })
            end

            def list_bsselect length, options = {}
                options.merge({
                    template: options[:optional] ? "fields/list_bsselect_opt" : "fields/list_bsselect",
                    length: length,
                    animation: BS_ANIMATION
                })
            end

            def list_buttons options = {}
                options.merge({
                    template: options[:optional] ? "fields/list_buttons_opt" : "fields/list_buttons"
                })
            end

            def select_picker options = {}
                options.merge({
                    template: options[:optional] ? "fields/select_picker_opt" : "fields/select_picker"
                })
            end

            def bsselect_picker options = {}
                options.merge({
                    template: options[:optional] ? "fields/bsselect_picker_opt" : "fields/bsselect_picker",
                    animation: BS_ANIMATION
                })
            end

            # def bs_select_picker(options)
            #     {
            #     	resource: options[:resource],
            #         template: "fields/bs_select"
            #     }
            # end

            def scaffold_picker options = {}
                options.merge({
                    template: 'fields/scaffold_picker'
                })
            end

            def typeahead_picker
                {template: "fields/typeahead_picker", animation: BS_ANIMATION}
            end

            def email length
                {template: "fields/email", length: length}
            end

            def date_range
                {template: "fields/date_range", animation: BS_ANIMATION}
            end

            def date_time
                {template: "fields/date_time", animation: BS_ANIMATION}
            end

            def currency
                {template: "fields/currency"}
            end

            def checkbox
                {template: "fields/checkbox"}
            end

            def checkbox_buttons options = {}
                options.merge({
                    template: options[:optional] ? "fields/checkbox_buttons_opt" : "fields/checkbox_buttons"
                })
            end

            def radio_checkbox
                {template: "fields/radio_checkbox"}
            end

            def scaffold
                {template: "fields/scaffold"}
            end

        end
    end

    class SearchTemplates
        class << self
            def input_text
                {template: "search_fields/input_text"}
            end

            def date_range options = {}
                options.merge({
                    template: "search_fields/date_range",
                    animation: BS_ANIMATION
                })
            end

            def integer_range
                {template: "search_fields/integer_range"}
            end

            def integer
                {template: "search_fields/integer"}
            end

            def select_picker options = {}
                options.merge({
                    template: "search_fields/select_picker"
                })
            end

            def bsselect_picker options = {}
                options.merge({
                    template: options[:multiple] ? "search_fields/bsmselect_picker" : "search_fields/bsselect_picker",
                    animation: BS_ANIMATION
                })
            end

            def scaffold_picker options = {}
                options.merge({
                    # template: options[:multiple] ? "search_fields/scaffold_picker" : "search_fields/scaffold_picker"
                    template: "search_fields/scaffold_picker"
                })
            end

            def typeahead_picker
                {template: "search_fields/typeahead_picker", animation: BS_ANIMATION}
            end

            # def checkbox_search true_v = "1", false_v = "0"
            #     {
            #         template: "search_fields/checkbox2",
            #         true_value: true_v,
            #         false_value: false_v
            #     }
            # end

            def checkbox_buttons
                {template: 'search_fields/checkbox_buttons'}
            end

            def list_select
                {template: "search_fields/list_select"}
            end

            def list_bsselect options = {}
                options.merge({
                    template: options[:multiple] ? "search_fields/list_bsmselect" : "search_fields/list_bsselect",
                    animation: BS_ANIMATION
                })
            end

            def list_buttons
                {template: "search_fields/list_buttons"}
            end

            def decimal_date
                {template: "search_fields/decimal_date_range", animation: BS_ANIMATION}
            end
        end
    end
end