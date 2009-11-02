#!/usr/bin/env ruby

require 'cgi'
require 'rubygems'
require 'mechanize'
require 'benchmark'
require 'getoptlong'

class Array
  def shuffle
    self.collect {|l| [l, rand] }.sort_by {|x| x[1]}.collect{|x| x[0]}
  end
end

def generate_form_submission(link, form)
  checked_by_name = { }
  form.fields.shuffle.each do |field|
    case field
    when WWW::Mechanize::Form::SelectList: field.value = field.options.shuffle.first
    when WWW::Mechanize::Form::MultiSelectList: field.value = field.options.shuffle[0..(rand * field.options.length).to_i]
    when WWW::Mechanize::Form::CheckBox: field.checked = !field.checked if rand < 0.25
    when WWW::Mechanize::Form::RadioButton
      if checked_by_name.has_key? field.name
        field.checked = false
        if checked_by_name[field_name] = false
          field.checked = true
        end
        checked_by_name[field_name] = true
      elsif rand < 0.25
        field.checked = !field.checked
        checked_by_name[field.name] = field.checked
      end
    when WWW::Mechanize::Form::Button:
    when WWW::Mechanize::Form::Field:
    end
  end
  action = ((form.action.nil? || form.action == '') ? link : form.action.to_s).gsub(/\?.*/, '')

  new_link = action + '?' + form.build_query.map { |key, value| CGI.escape(key) + '=' + CGI.escape(value) }.join("&")
end

def get_remote_host(link)
  begin
    uri = link.uri
    if (uri.host)
      return uri.host + ":" + (uri.port.to_s || '80')
    end
  rescue
  end

  return nil
end

def sanitize(href)
  begin
    href.gsub(/^http:\/\/[a-z\.]+:\d+/,'')\
    .gsub(/^\/document\/other\/[A-Za-z0-9\%\-\:]+/,'/document/other/#')\
    .gsub(/\?.*/, '')\
    .gsub(/\.\w+/, '.format')\
    .gsub(/\d+/,'#')\
    .gsub(/(\w+)=[^&]+/,'\1=#')
  rescue
  end
end

def get_links(page, site, verboten_paths)
  links = []

  if !page.nil? && page.respond_to?(:links)
    page.links.each do |potential_link|

      remote_host = get_remote_host(potential_link)
      next if remote_host && remote_host != site

      href = potential_link.href
      next unless href && href != ""

      href = href.gsub(/^http:..localhost:3000/,'')

      next if href =~ /^\#/;
      next if href =~ /application\/x-shockwave-flash/
      next if href =~ /deactivate|reactivate|cheat|logout|change|delete|create|login|edit|destroy|mailto:|add_to_program|javascript:|move_to_|move_up|move_down/
      next if verboten_paths.any? { |regex| href =~ regex }

      links.push href
    end
  end
  return links
end

def get_unvisited_links(links, visited_links)
  links_with_sanitize = links.shuffle.collect {|l| [sanitize(l), l] }

  unvisited_links = links_with_sanitize.select {|l|
    if visited_links[l.first] >= @limit_url_types || visited_links.has_key?(l.last)
      false
    else
      visited_links[l.first] ||= 0
      visited_links[l.first] += 1
      visited_links[l.last] = 1
      true
    end
  }

  unvisited_links.collect {|l| l.last }
end


def spider(options)
  site           = options['--host'          ]
  controller     = options['--controller'    ]
  login          = options['--username'      ]
  password       = options['--password'      ]
  login_target   = options['--login-target'  ]
  login_field    = options['--username-field']
  password_field = options['--password-field']
  verboten_paths = options['--verboten-paths']

  agent = WWW::Mechanize.new
  agent.read_timeout = 300

  links = []
  visited_links = Hash.new(0)
  num_pages_loaded = 0

  page = agent.post( 'http://' + site + login_target, { login_field => login, password_field => password })

  puts "Logged in "

  links = @initial_url ? [[@initial_url, ""]] : []
  links += controller ? [ [ "/" + controller, ""] ] : get_unvisited_links(get_links(page, site, verboten_paths), visited_links).collect { |href| [href, "(login)"] }

  failures      = []
  long_requests = []

  total_time = Benchmark.measure do
    begin
      link, referer = *links.shift
      page = nil
      response_code = 200

      time = Benchmark.measure do
        begin
          STDOUT.write "Fetching #{ link }\r"
          STDOUT.flush
          page = agent.get(link)
        rescue WWW::Mechanize::ResponseCodeError
          response_code = $!.response_code
          failures << [response_code, link, referer]
        rescue Timeout::Error
          response_code = -1
          failures << [response_code, link, referer]
        rescue WWW::Mechanize::UnsupportedSchemeError
          response_code = 0
          puts "Unsupported scheme: $!"
        rescue
          puts "Unknown error: #{ $! }"
        end
      end

      if time.real > 5
        long_requests << [time.real, link, referer]
      end

      title = page.nil?                  ? "(Failure; linked from #{referer})" \
      : page.respond_to?(:title) ? (page.title||'')[0..39]  \
      :                          "(Unknown)"
      title = title.gsub(/\s+/, ' ')

      puts "[%4d %6d %3d %4.1fs] %-40s | %-70s %s" % [
                                                   links.size,
                                                   page ? page.body.size : 0,
                                                   response_code,
                                                   time.real,
                                                   title,
                                                   link,
                                                   (referer || '').match(/\[GET\]/) ? "(GET)" : ""
      ]

      if page && page.body.size < 50_000
        if page.respond_to? :forms
          forms = page.forms.select { |f| f.method.upcase == 'GET' }
          form_submissions = forms.map { |f| (1..@limit_url_types).map { generate_form_submission(link, f) }.uniq }.flatten
          form_submissions = get_unvisited_links(form_submissions, visited_links)
          links += form_submissions.collect { |href| [href.to_s, link.to_s + " [GET]"] }
        end

        links += get_unvisited_links(get_links(page, site, verboten_paths), visited_links) \
                .select { |href| !controller || controller == "" || href.index(controller) == 1 } \
                .collect { |href| [href, link] }
      end

      num_pages_loaded += 1
      # break if num_pages_loaded >= 20  #temp

    end while links.size > 0  #(end)
  end

  ##### Print summary info

  puts '-' * 75, "\nLoaded #{num_pages_loaded} pages in %.1f seconds." % total_time.real

  if (failures.size > 0)
    puts "\nFailures: "

    failures.each do |f|
      puts "%d\t%s\tfrom: %s" % f
    end
  end

  if (long_requests.size > 0)
    puts "\nLong-running requests (more than 5s): "

    # Reverse sort entries in long_requests by elapsed time
    long_requests.sort.reverse.each do |e|
      puts "%4.1fs  |  %s  |  %s" % e
    end
  end
end



##### Process command-line arguments
opts = {
  '--verboten-paths' => [],
}

cmd_line_options = [
  ["--host",                GetoptLong::REQUIRED_ARGUMENT],
  ["--username",            GetoptLong::REQUIRED_ARGUMENT],
  ["--password",            GetoptLong::REQUIRED_ARGUMENT],
  ["--login-target",        GetoptLong::REQUIRED_ARGUMENT],
  ["--username-field",      GetoptLong::REQUIRED_ARGUMENT],
  ["--password-field",      GetoptLong::REQUIRED_ARGUMENT],
  ["--controller",          GetoptLong::REQUIRED_ARGUMENT],
  ["--limit-url-types",     GetoptLong::REQUIRED_ARGUMENT],
  ["--initial-url",         GetoptLong::REQUIRED_ARGUMENT],
  ["--verboten-path-regex", GetoptLong::REQUIRED_ARGUMENT],
]
GetoptLong.new(*cmd_line_options).each do |opt, val|
  if opt == '--verboten-path-regex'
    opts['--verboten-paths'] << Regexp.new(val, Regexp::IGNORECASE)
  else
    opts[opt] = val
  end
end
opts['--host'] ||= 'localhost:3000'

@limit_url_types = (opts['--limit-url-types'] || "20").to_i
@initial_url = opts['--initial-url']


##### Launch the spider
spider(opts)
