require File.join(File.dirname(__FILE__), *%w[dependencies])

module SiteSpider

  def go!(options = {});
    Spider.new(options).go!
  end
  module_function :go!



  class Spider
    include SiteSpider::Helpers

    attr_accessor :site, :controller, :verboten_paths
    attr_accessor :login_target, :login_field, :login, :password_field, :password
    attr_accessor :agent, :links, :visited_links, :num_pages_loaded, :limit_url_types, :initial_url
    attr_accessor :failures, :long_requests

    def initialize(options = {})
      # Set properties from command-line options
      self.site            = options['--host'           ]
      self.controller      = options['--controller'     ]
      self.login           = options['--username'       ]
      self.password        = options['--password'       ]
      self.login_target    = options['--login-target'   ]
      self.login_field     = options['--username-field' ]
      self.password_field  = options['--password-field' ]
      self.verboten_paths  = options['--verboten-paths' ]
      self.limit_url_types = options['--limit-url-types'].to_i || 20
      self.initial_url     = options['--initial-url'    ]

      self.agent = WWW::Mechanize.new
      agent.read_timeout = 300

      self.links            = []
      self.failures         = []
      self.long_requests    = []
      self.visited_links    = Hash.new(0)
      self.num_pages_loaded = 0

      if initial_url
        links << [initial_url, ""]
      end
    end

    def go!
      total_time = Benchmark.measure do
        log_in_and_seed_links!

        while links.length > 0
          page_info = get_next_page!  # this should eventually be threaded
                                      # (note that there are some mutex points in here)

          ### Critical section:  at puts time, we should display an accurate count of links remaining
          ### Note that in order to really be accurate, the number of pending threads should be taken into account
          parse_page_for_links!(page_info)
          print_page_summary(page_info)
          ### End critical section

          # break if num_pages_loaded >= 5  #temp
        end
      end

      print_final_summary(total_time)
    end

    protected
    def log_in_and_seed_links!
      # First, log in
      page_info = PageInfo.new
      page_info.referer = '[LOGIN PAGE]'
      page_info.link = 'http://' + site + login_target
      page_info.time = Benchmark.measure do
        page_info.page = agent.post(page_info.link, { login_field => login, password_field => password })
      end

      # Then, seed links
      self.links << ["/" + controller, ""] if controller
      parse_page_for_links!(page_info)

      # Last, print some summary data
      puts "Logged in "
      print_page_summary(page_info)
    end

    def get_next_page!
      page_info = PageInfo.new

      link_data = links.shift   ### MUTEX THIS
      page_info.link, page_info.referer = *(link_data)

      page_info.time = Benchmark.measure do
        begin
          page_info.page = agent.get(page_info.link)
        rescue WWW::Mechanize::ResponseCodeError
          page_info.response_code = $!.response_code
          failures << page_info
        rescue Timeout::Error
          page_info.response_code = -1
          failures << page_info
        rescue WWW::Mechanize::UnsupportedSchemeError
          page_info.response_code = 0
          puts "Unsupported scheme: $!"
        rescue
          puts "Unknown error: #{ $! }"
        end
      end

      if page_info.time.real > 5
        long_requests << page_info    ### MUTEX THIS
      end

      self.num_pages_loaded += 1   ### MUTEX THIS

      page_info
    end

    def print_page_summary(page_info)
      title = if page_info.page.nil?
        "(FAIL, from: #{page_info.referer})"
      else
        if page_info.page.respond_to?(:title)
          (page_info.page.title || '')[0..39]
        else
          "(Unknown)"
        end
      end
      title.gsub!(/\s+/, ' ')

      puts "[%4d %6dK %3d %4.1fs] %-40s | %-70s %s" % [
        links.length,
        page_info.body_size / 1024,
        page_info.response_code,
        page_info.time.real,
        title,
        page_info.link,
        (page_info.referer || '').match(/\[GET\]/) ? "(GET)" : ""
      ]
    end

    def parse_page_for_links!(page_info)
      page = page_info.page
      link = page_info.link
      referer = link.dup.to_s
      if page_info.body_size < 50_000
        if page.respond_to? :forms
          forms = page.forms.select { |f| f.method.upcase == 'GET' }
          form_submissions = forms.map { |f| (1..limit_url_types).map { generate_form_submission(link, f) }.uniq }.flatten
          form_submissions = get_unvisited_links(form_submissions, visited_links, limit_url_types)
          self.links += form_submissions.map { |href| [href.to_s, referer + " [GET]"] }
        end

        links = get_links(page, site, verboten_paths)
        links = get_unvisited_links(links, visited_links, limit_url_types)
        links = get_links_matching_controller(links, controller)
        self.links += links.map { |href| [href, referer] }
      end
    end

    def print_final_summary(total_time)
      puts '-' * 75, "\nLoaded #{num_pages_loaded} pages in %.1f seconds." % total_time.real

      unless failures.empty?
        puts "\nFailures: "

        failures.each do |page_info|
          puts "%d\t%s\tfrom: %s" % [page_info.response_code, page_info.link, page_info.referer]
        end
      end

      unless long_requests.empty?
        puts "\nLong-running requests (more than 5s): "

        # Reverse sort entries in long_requests by elapsed time
        long_requests.sort.reverse.each do |page_info|
          puts "%4.1fs  |  %s  |  %s" % [page_info.time.real, page_info.link, page_info.referer]
        end
      end
    end
  end

end


