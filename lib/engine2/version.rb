# coding: utf-8

module Engine2
    MAJOR, MINOR, TINY = [1, 0, 0]
    VERSION = [MAJOR, MINOR, TINY].join('.').freeze
    def self.version
        VERSION
    end
end