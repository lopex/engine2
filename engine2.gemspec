# coding: utf-8

require File.expand_path("../lib/engine2/version", __FILE__)

Gem::Specification.new do |spec|
    spec.name          = "engine2"
    spec.version       = Engine2::VERSION
    spec.authors       = ["lopex"]
    spec.email         = ["lopx@gazeta.pl"]

    spec.summary       = "Tree based routing framework with scaffolding support"
    spec.description   = spec.summary
    spec.homepage      = "http://none.for.now"
    spec.license       = 'MIT'

    spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
    spec.require_paths = ["lib"]

    spec.add_dependency "sequel", '~> 4'
    if defined? JRUBY_VERSION
        spec.add_dependency 'jdbc-sqlite3', '~> 3.8'
    else
        spec.add_dependency 'sqlite3', '~> 1.3'
    end
    spec.add_dependency "sinatra", '~> 2.0'
    spec.add_dependency 'slim', '~> 3.0'
    spec.add_dependency 'faye-websocket', '~> 0.10'

    spec.add_development_dependency "bundler", "~> 1.11"
    spec.add_development_dependency "rake", "~> 11"
end
