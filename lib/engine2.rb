# coding: utf-8

require 'yaml'
require 'logger'
require 'sequel'
require 'sinatra'
require 'json'
require 'slim'
require 'tilt/coffee'
require 'engine2/version'

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
    require "engine2/#{f}"
end

Engine2.bootstrap