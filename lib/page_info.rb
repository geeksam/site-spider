module SiteSpider
  class PageInfo
    attr_accessor :link, :referer, :page, :time, :response_code
    def initialize
      self.response_code = 200  # assume OK by default
    end

    def body_size
      (page && page.body && page.body.size) || 0
    end
  end
end
