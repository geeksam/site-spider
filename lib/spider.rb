require File.join(File.dirname(__FILE__), *%w[dependencies])

module SiteSpider

  def go!(options = {});
    Spider.new(options).go!
  end
  module_function :go!



  class Spider
    include SiteSpider::Helpers

    Defaults = {
      :limit_url_types         => 20,
      :max_concurrent_requests => 1,
    }

    attr_accessor :site, :controller, :verboten_paths
    attr_accessor :login_target, :login_field, :login, :password_field, :password
    attr_accessor :links, :visited_links, :num_pages_loaded, :total_page_load_time, :limit_url_types, :initial_url
    attr_accessor :failures, :long_requests
    attr_accessor :max_concurrent_requests

    def initialize(options = {})
      initialize_process_options(options)
      initialize_set_up_thread_management
      initialize_create_an_agent_for_each_thread
      initialize_set_up_summary_variables
    end

    protected
    def initialize_process_options(options)
      self.site                    = options['--host'                   ]
      self.controller              = options['--controller'             ]
      self.login                   = options['--username'               ]
      self.password                = options['--password'               ]
      self.login_target            = options['--login-target'           ]
      self.login_field             = options['--username-field'         ]
      self.password_field          = options['--password-field'         ]
      self.initial_url             = options['--initial-url'            ]
      self.verboten_paths          = options['--verboten-paths'         ]
      self.limit_url_types         = options['--limit-url-types'        ]
      self.max_concurrent_requests = options['--max-concurrent-requests']

      self.limit_url_types         = (self.limit_url_types         || Defaults[:limit_url_types]        ).to_i
      self.max_concurrent_requests = (self.max_concurrent_requests || Defaults[:max_concurrent_requests]).to_i
    end
    def initialize_set_up_thread_management
      @thread_pool   = ThreadPool.new(max_concurrent_requests)
      @links_mutex   = Mutex.new
      @summary_mutex = Mutex.new
      @agents_mutex  = Mutex.new
    end
    def initialize_create_an_agent_for_each_thread
      # Per the Mechanize mailing list, each thread should have its own agent.
      # http://rubyforge.org/pipermail/mechanize-users/2009-September/000449.html
      @agents = []
      max_concurrent_requests.times do |i|
        agent = WWW::Mechanize.new
        agent.read_timeout = 300
        @agents << agent
      end
    end
    def initialize_set_up_summary_variables
      self.links                = []
      if initial_url
        links << [initial_url, ""]
      end

      self.failures             = []
      self.long_requests        = []
      self.visited_links        = Hash.new(0)
      self.num_pages_loaded     = 0
      self.total_page_load_time = 0.0
    end
    public

    def go!
      keep_running = true

      total_time = Benchmark.measure do
        log_in_and_seed_links!
        @more_links = !links.empty?

        begin
          while keep_running && @more_links
            ## IMPORTANT NOTE:
            ## Without the following line, we'll create new threads as fast as this while loop can execute.
            ## Doing so sucks up memory like nobody's business, and makes interrupts (e.g., ^C) take forever
            ## as all of those threads wake up and terminate.
            next if @agents.empty?

	          @thread_pool.dispatch do    ##### THREADED SECTION #####
              begin
  	            agent = acquire_agent
                if keep_running
  		            page_info = get_next_page!(agent)
  		            process_page_info(page_info) if page_info
  	            end
              ensure
		            # release the agent
		            @agents << agent
              end
	          end                         ##### END THREADED SECTION #####
	        end
        rescue Interrupt => e
          keep_running = false
          puts "Interrupt received!  Waiting on #{@thread_pool.size} thread(s) to return..."
        end

        @thread_pool.shutdown
      end

      print_final_summary(total_time) if keep_running
    end

    protected
    def acquire_agent
      agent = nil
      while agent.nil?
        @agents_mutex.synchronize { agent = @agents.shift }
      end
      agent
    end

    def process_page_info(page_info)
      @links_mutex.synchronize do
        parse_page_for_links!(page_info)
        @more_links = !links.empty?
      end
      @summary_mutex.synchronize do
        if page_info.time.real > 5
          long_requests << page_info    ### MUTEX THIS
        end
        self.num_pages_loaded     += 1
        self.total_page_load_time += page_info.time.real
        print_page_summary(page_info)
      end
    end

    def log_in_and_seed_links!
      # First, log in
      page_info = PageInfo.new
      page_info.referer = '[LOGIN PAGE]'
      page_info.link = 'http://' + site + login_target
      page_info.time = Benchmark.measure do
        @agents.each do |agent|
          page_info.page = agent.post(page_info.link, { login_field => login, password_field => password })
        end
      end

      # Then, seed links
      self.links << ["/" + controller, ""] if controller
      parse_page_for_links!(page_info)

      # Last, print some summary data
      puts "Logged in "
      print_page_summary(page_info)
    end

    def get_next_page!(agent)
      link_data = nil  # get this out of scope of the synchronize block
      @links_mutex.synchronize do
        link_data = links.shift
      end
      return if link_data.nil?

      page_info = PageInfo.new
      page_info.link     = link_data.first
      page_info.referer  = link_data.last

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
        rescue Exception => e
          puts "Unknown error: #{ e.inspect }"
          # puts e.backtrace
        end
      end

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

      puts '[%4d %6dK %3d %4.1fs] %-40s | %-70s %s' % [
        links.length,   # note that this is only approximate
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
      puts "\n" + '-' * 75
      puts "\nLoaded %d pages in ~%.0f seconds." % [
        num_pages_loaded,
        total_time.real,
      ]
      puts "Total page load time was ~%.0f seconds, split across %d threads." % [
        total_page_load_time,
        max_concurrent_requests,
      ]

      unless failures.empty?
        puts "\nFailures: "

        failures.sort_by{ |e| [e.response_code, e.link] }.each do |page_info|
          puts "%d\t%s\tfrom: %s" % [page_info.response_code, page_info.link, page_info.referer]
        end
      end

      unless long_requests.empty?
        puts "\nLong-running requests (more than 5s): "

        # Reverse sort entries in long_requests by elapsed time
        long_requests.sort_by { |e| e.time.real }.reverse.each do |page_info|
          puts "%4.1fs  |  %-40s  |  %s" % [page_info.time.real, page_info.link, page_info.referer]
        end
      end
    end
  end

end
