source "http://rubygems.org"

gem 'sequel'

if defined? JRUBY_VERSION
    gem 'torquebox', '=4.0.0.beta2'
    gem 'jdbc-sqlite3'
else
    gem 'thin'
    gem 'sqlite3'
end

gem "execjs"
gem "sinatra"
gem 'slim'
gem 'coffee-script'

group :assets do
	gem 'slim'
	gem 'coffee-script'
    gem 'uglifier'
    gem "yui-compressor"
end