# coding: utf-8
# frozen-string-literal: true

require 'yaml'
require 'logger'
require 'sequel'
require 'sinatra'
require 'json'
require 'slim'
require 'engine2/version'
require 'faye/websocket'

%w[
    core.rb
    handler.rb
    type_info.rb
    model.rb
    templates.rb
    action.rb
    action_node.rb
    scheme.rb

    action/array.rb
    action/list.rb
    action/view.rb
    action/form.rb
    action/save.rb
    action/delete.rb
    action/decode.rb
    action/link.rb
    action/infra.rb
].each do |f|
    load "engine2/#{f}"
end
