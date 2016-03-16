# coding: utf-8

require 'yaml'
require 'logger'
require 'sequel'
require 'sinatra'
require 'json'
require 'engine2/version'

module Engine2
    PATH ||= File.expand_path('..', File.dirname(__FILE__))

    %w[
        core.rb
        handler.rb
        type_info.rb
        model.rb
        templates.rb
        meta.rb
        action.rb
        scheme.rb

        meta/list_meta.rb
        meta/view_meta.rb
        meta/form_meta.rb
        meta/save_meta.rb
        meta/delete_meta.rb
        meta/decode_meta.rb
        meta/link_meta.rb
        meta/infra_meta.rb
    ].each do |f|
        load "engine2/#{f}" rescue puts $!
        # require "/engine2/#{f}"
    end

    e2_db_file = (defined? JRUBY_VERSION) ? "jdbc:sqlite:#{APP_LOCATION}/engine2.db" : "sqlite://#{APP_LOCATION}/engine2.db"
    E2DB ||= connect e2_db_file, loggers: [Logger.new($stdout)], convert_types: false, name: :engine2
    DUMMYDB ||= Sequel::Database.new uri: 'dummy'

    self.core_loading = false

    def self.database name
        Object.const_set(name, yield) unless Object.const_defined?(name)
    end

    def self.boot &blk
        @boot_blk = blk
    end

    def self.bootstrap app = APP_LOCATION
        require 'engine2/pre_bootstrap'
        t = Time.now
        Action.count = 0
        SCHEMES.clear

        load "#{app}/boot.rb"

        Sequel::DATABASES.each &:load_schema_cache_from_file
        load 'engine2/models/Files.rb'
        load 'engine2/models/UserInfo.rb'
        Dir["#{app}/models/*"].each{|m| load m}
        puts "MODELS, Time: #{Time.now - t}"
        Sequel::DATABASES.each &:dump_schema_cache_to_file

        SCHEMES.merge!
        Engine2.send(:remove_const, :ROOT) if defined? ROOT
        Engine2.const_set(:ROOT, Action.new(nil, :api, DummyMeta, {}))

        @boot_blk.(ROOT)
        ROOT.setup_action_tree
        puts "BOOTSTRAP #{app}, Time: #{Time.new - t}"
        require 'engine2/post_bootstrap'
    end
end
