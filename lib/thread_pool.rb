module SiteSpider
  
  # From the Ruby Cookbook, with one change
  class ThreadPool
    def initialize(max_size)
      @pool = []
      @max_size = max_size
      @pool_mutex = Mutex.new
      @pool_cv = ConditionVariable.new  
    end

    def size
      @pool.size
    end

    def dispatch(*args)    
      Thread.new do
        # Wait for space in the pool.
        @pool_mutex.synchronize do
          while @pool.size >= @max_size          
            print "Pool is full; waiting to run #{args.join(',')}...\n" if $DEBUG_THREAD_POOL
            # Sleep until some other thread calls @pool_cv.signal.
            @pool_cv.wait(@pool_mutex)
          end
          # NOTE: the Ruby Cookbook example performed the following line outside the #synchronize block.
          #       I moved it here after noticing that { @pool.size > @max_size } was sometimes true.
          @pool << Thread.current
        end

        begin
          yield(*args)
        rescue => e
          exception(self, e, *args)
        ensure
          @pool_mutex.synchronize do
            # Remove the thread from the pool.
            @pool.delete(Thread.current)
            # Signal the next waiting thread that there's a space in the pool.
            @pool_cv.signal            
          end
        end
      end
    end

    def shutdown
      @pool_mutex.synchronize { @pool_cv.wait(@pool_mutex) until @pool.empty? }
    end

    def exception(thread, exception, *original_args)
      # Subclass this method to handle an exception within a thread.
      puts "Exception in thread #{thread}: #{exception}"
      puts exception.backtrace.join("\n")
    end  
  end
end
$DEBUG_THREAD_POOL = false