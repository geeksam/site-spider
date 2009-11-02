module SiteSpider

  module Helpers
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

    def get_unvisited_links(links, visited_links, limit_url_types)
      links_with_sanitize = links.shuffle.collect {|l| [sanitize(l), l] }

      unvisited_links = links_with_sanitize.select {|l|
        if visited_links[l.first] >= limit_url_types || visited_links.has_key?(l.last)
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

    def get_links_matching_controller(links, controller)
      links.select { |href| !controller || controller == "" || href.index(controller) == 1 }
    end
  end

end
