# coding: utf-8
# frozen_string_literal: true

module Engine2
    MAJOR, MINOR, TINY = [1, 0, 4]
    VERSION = [MAJOR, MINOR, TINY].join('.').freeze
    def self.version
        VERSION
    end
end