module Imdb
  # Represents something on IMDB.com
  class Base
    attr_accessor :id, :url, :title, :also_known_as

    # Initialize a new IMDB movie object with it's IMDB id (as a String)
    #
    #   movie = Imdb::Movie.new("0095016")
    #
    # Imdb::Movie objects are lazy loading, meaning that no HTTP request
    # will be performed when a new object is created. Only when you use an
    # accessor that needs the remote data, a HTTP request is made (once).
    #
    def initialize(imdb_id, title = nil)
      @id = imdb_id
      @url = "http://www.imdb.com/title/tt#{imdb_id}/combined"
      @title = title.gsub(/"/, '').strip if title
    end

    # Returns an array with cast members
    def cast_members
      document.search('table.cast td.nm a').map { |link| link.content.strip } rescue []
    end

    def cast_member_ids
      document.search('table.cast td.nm a').map { |l| l['href'].sub(%r{^/name/(.*)/}, '\1') }
    end

    # Returns an array with cast characters
    def cast_characters
      document.search('table.cast td.char').map { |link| link.content.strip } rescue []
    end

    # Returns an array with cast members and characters
    def cast_members_characters(sep = '=>')
      memb_char = []
      cast_members.each_with_index do |_m, i|
        memb_char[i] = "#{cast_members[i]} #{sep} #{cast_characters[i]}"
      end
      memb_char
    end

    # Returns the name of the director
    def director
      document.search("h5[text()^='Director'] ~ div a").map { |link| link.content.strip } rescue []
    end

    # Returns the names of Writers
    def writers
      writers_list = []

      fullcredits_document.search("h4[text()^='Writing Credits'] + table tbody tr td[class='name']").each_with_index do |name, i|
        writers_list[i] = name.content.strip unless writers_list.include? name.content.strip
      end rescue []

      writers_list
    end

    # Returns the url to the "Watch a trailer" page
    def trailer_url
      'http://imdb.com' + document.at("a[@href*='/video/screenplay/']")['href'] rescue nil
    end

    # Returns an array of genres (as strings)
    def genres
      #document.search("h5[text()='Genre:'] ~ div a[@href*='/Sections/Genres/']").map { |link| link.content.strip } rescue []
      document.search("div.titlereference-header a[@href^='/genre/']").map { |link| link.content.strip } rescue []
    end

    # Returns an array of languages as strings.
    def languages
      document.search("h5[text()='Language:'] ~ div a[@href*='/language/']").map { |link| link.content.strip } rescue []
    end

    # Returns an array of countries as strings.
    def countries
      document.search("h5[text()='Country:'] ~ div a[@href*='/country/']").map { |link| link.content.strip } rescue []
    end

    # Returns the duration of the movie in minutes as an integer.
    def length
      document.at("h5[text()='Runtime:'] ~ div").content[/\d+ min/].to_i rescue nil
    end

    # Returns the company
    def company
      document.search("h5[text()='Company:'] ~ div a[@href*='/company/']").map { |link| link.content.strip }.first rescue nil
    end

    # Returns a string containing the plot.
    def plot
      #sanitize_plot(document.at("h5[text()='Plot:'] ~ div").content) rescue nil
      sanitize_plot(document.at('section.titlereference-section-overview > div').content.strip) rescue nil
    end

    # Returns a string containing the plot summary
    def plot_synopsis
      doc = Nokogiri::HTML(Imdb::Movie.find_by_id(@id, :synopsis))
      doc.at("div[@id='swiki.2.1']").content.strip rescue nil
    end

    def plot_summary
      doc = Nokogiri::HTML(Imdb::Movie.find_by_id(@id, :plotsummary))
      doc.at('p.plotSummary').inner_html.gsub(/<i.*/im, '').strip.imdb_unescape_html rescue nil
    end

    # Returns a string containing the URL to the movie poster.
    def poster
      src = document.at("a[@name='poster'] img")['src'] rescue nil
      case src
      when /^(http:.+@@)/
        Regexp.last_match[1] + '.jpg'
      when /^(http:.+?)\.[^\/]+$/
        Regexp.last_match[1] + '.jpg'
      end
    end

    # Returns a float containing the average user rating
    def rating
      doc = Nokogiri::HTML(Imdb::Movie.find_by_id(@id, :ratings))
      #doc.css('div#tn15.ratings div#tn15main div#tn15content p')[0].text.match(/IMDb users have given a weighted average vote of (\d[\d.]+) \/ 10/).captures[0] rescue nil
      doc.css('div#main div.title-ratings-sub-page div.allText')[0].text.gsub(/\s+/," ").match(/IMDb users have given a weighted average vote of (\d[\d.]+) \/ 10/).captures[0] rescue nil
    end
    
    # Returns an int containing the Metascore
    def metascore
      criticreviews_document.at('//span[@itemprop="ratingValue"]').content.to_i rescue nil
    end

    # Returns an int containing the number of user ratings
    def votes
      doc = Nokogiri::HTML(Imdb::Movie.find_by_id(@id, :ratings))
      #doc.css('div#tn15.ratings div#tn15main div#tn15content p')[0].text.match(/(\d+) IMDb users have given/).captures[0] rescue nil
      doc.css('div#main div.title-ratings-sub-page div.allText')[0].text.gsub(/\s+/," ").match(/([,\d]+) IMDb users have given/).captures[0].gsub(/,/,'') rescue nil
    end

    # Returns a string containing the tagline
    def tagline
      document.search("h5[text()='Tagline:'] ~ div").first.inner_html.gsub(/<.+>.+<\/.+>/, '').strip.imdb_unescape_html rescue nil
    end

    # Returns a string containing the mpaa rating and reason for rating
    def mpaa_rating
      #document.at("//a[starts-with(.,'MPAA')]/../following-sibling::*").content.strip rescue nil
      document.at("a[@href^='/search/title?certificates=US%3A']").text.strip.gsub(/^United States:/, '') rescue nil
    end

    # Returns a string containing the title
    def title(force_refresh = false)
      if @title && !force_refresh
        @title
      else
        #@title = document.at('.combined h1').inner_html.split('<span').first.strip.imdb_unescape_html rescue nil
        @title = document.at("//h3[@itemprop = 'name']").inner_html.split('<span').first.strip.imdb_unescape_html rescue nil
      end
    end

    # Returns an integer containing the year (CCYY) the movie was released in.
    def year
      #document.at("a[@href^='/year/']").content.to_i rescue nil
       document.at("//h3[@itemprop = 'name']//a[@itemprop = 'url']").text.to_i rescue nil
    end

    # Returns release date for the movie.
    def release_date
      sanitize_release_date(document.at("h5[text()*='Release Date'] ~ div").content) rescue nil
    end

    # Returns filming locations from imdb_url/locations
    def filming_locations
      locations_document.search('#filming_locations_content .soda dt a').map { |link| link.content.strip } rescue []
    end

    # Returns alternative titles from imdb_url/releaseinfo
    def also_known_as
      releaseinfo_document.search('#akas tr').map do |aka|
        {
          version: aka.search('td:nth-child(1)').text,
          title:   aka.search('td:nth-child(2)').text
        }
      end rescue []
    end

    private

    # Returns a new Nokogiri document for parsing.
    def document
      @document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id))
    end

    def locations_document
      @locations_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'locations'))
    end

    def releaseinfo_document
      @releaseinfo_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'releaseinfo'))
    end

    def fullcredits_document
      @fullcredits_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'fullcredits'))
    end
    
    def criticreviews_document
      @criticreviews_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'criticreviews'))
    end
    
    # Use HTTParty to fetch the raw HTML for this movie.
    def self.find_by_id(imdb_id, page = :combined)
      open("http://www.imdb.com/title/tt#{imdb_id}/#{page}")
    end

    # Convenience method for search
    def self.search(query)
      Imdb::Search.new(query).movies
    end

    def self.top_250
      Imdb::Top250.new.movies
    end

    def sanitize_plot(the_plot)
      the_plot = the_plot.gsub(/add\ssummary|full\ssummary/i, '')
      the_plot = the_plot.gsub(/add\ssynopsis|full\ssynopsis/i, '')
      the_plot = the_plot.gsub(/\u00BB|\u00A0/i, '')
      the_plot = the_plot.gsub(/\|/i, '')
      the_plot.strip
    end

    def sanitize_release_date(the_release_date)
      the_release_date.gsub(/see|more|\u00BB|\u00A0/i, '').strip
    end
  end # Movie
end # Imdb
