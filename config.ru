# coding: utf-8
Encoding.default_external = "utf-8"

$: << File.expand_path(File.dirname(__FILE__))

APP_LOCATION = (defined?(JRUBY_VERSION) ? File.dirname(__FILE__) + '/' : '') + 'apps/test'

require 'tilt/coffee' # eager
require 'bundler'
Bundler.require
load './lib/engine2.rb'

Engine2.bootstrap
run Engine2::Handler
