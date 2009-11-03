#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), *%w[lib spider])

##### Process command-line arguments
opts = {
  '--verboten-paths' => [],
}

cmd_line_options = [
  ["--host",                    GetoptLong::REQUIRED_ARGUMENT],
  ["--username",                GetoptLong::REQUIRED_ARGUMENT],
  ["--password",                GetoptLong::REQUIRED_ARGUMENT],
  ["--login-target",            GetoptLong::REQUIRED_ARGUMENT],
  ["--username-field",          GetoptLong::REQUIRED_ARGUMENT],
  ["--password-field",          GetoptLong::REQUIRED_ARGUMENT],
  ["--controller",              GetoptLong::REQUIRED_ARGUMENT],
  ["--limit-url-types",         GetoptLong::REQUIRED_ARGUMENT],
  ["--initial-url",             GetoptLong::REQUIRED_ARGUMENT],
  ["--verboten-path-regex",     GetoptLong::REQUIRED_ARGUMENT],
  ["--max-concurrent-requests", GetoptLong::REQUIRED_ARGUMENT],
]
GetoptLong.new(*cmd_line_options).each do |opt, val|
  if opt == '--verboten-path-regex'
    opts['--verboten-paths'] << Regexp.new(val, Regexp::IGNORECASE)
  else
    opts[opt] = val
  end
end
opts['--host'] ||= 'localhost:3000'


##### Launch the spider
SiteSpider.go!(opts)
