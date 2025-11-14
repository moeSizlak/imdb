module Imdb
  # Represents something on IMDB.com

  $browser = Ferrum::Browser.new({:process_timeout => 30})
  $browser_mutex = Mutex.new

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
      document.css("div[data-testid='sub-section-cast'] li[data-testid='name-credits-list-item'] a.name-credits--title-text-big").map { |link| link.content.strip } rescue []
    end

    def cast_member_ids
      document.css("div[data-testid='sub-section-cast'] li[data-testid='name-credits-list-item'] a.name-credits--title-text-big").map { |link| link['href'].gsub(/^.*\/name\/([^?\/]*).*/, '\1') } rescue []
    end

    # Returns an array with cast characters
    def cast_characters
      document.css("div[data-testid='sub-section-cast'] li[data-testid='name-credits-list-item'] a[href*=character]").map { |link| link.content.strip } rescue []
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
      jsonld.dig('director',0,'name')
    end

    # Returns the names of Writers
    def writers
      document.css("div[data-testid='sub-section-writer'] li[data-testid='name-credits-list-item'] a.name-credits--title-text-big").map { |link| link.content.strip } rescue []
    end

    # Returns the url to the "Watch a trailer" page
    def trailer_url
      jsonld.dig('trailer','url')
    end

    # Returns an array of genres (as strings)
    def genres
      jsonld['genre'] || []
    end

    # Returns an array of languages as strings.
    def languages
      document.css("li[data-testid='title-details-languages'] li a").map { |link| link.content.strip } rescue []
    end

    # Returns an array of countries as strings.
    def countries
      document.css("li[data-testid='title-details-origin'] li a").map { |link| link.content.strip } rescue []
    end

    # Returns the duration of the movie in minutes as an integer.
    def length
      (Duration.new(jsonld["duration"]).total_minutes) rescue nil
    end

    # Returns the company
    def companies
      document.css("li[data-testid='title-details-companies'] li a").map { |link| link.content.strip } rescue []
    end

    def company
      companies.first rescue nil
    end    

    # Returns a string containing the plot.
    def plot
      HTMLEntities.new.decode jsonld["description"] rescue nil
    end

    # Returns a string containing the plot summary
    def plot_synopsis
      synopsis_document.at_css("div[@data-testid='sub-section-synopsis']/ul/li").content rescue nil
    end

    def plot_summary
      HTMLEntities.new.decode jsonld['description'] rescue nil
    end

    # Returns a string containing the URL to the movie poster.
    def poster
      jsonld['image'] rescue nil
    end

    # Returns a float containing the average user rating
    def rating
      jsonld.dig('aggregateRating','ratingValue')
    end
    
    # Returns an int containing the Metascore
    def metascore
      criticreviews_document.at_css("div[@data-testid='critic-reviews-title'] div").content.strip.imdb_unescape_html rescue nil
    end

    # Returns an int containing the number of user ratings
    def votes
      jsonld.dig('aggregateRating','ratingCount')
    end

    # Returns a string containing the tagline
    def tagline
      document.at_css("li[@data-testid = 'storyline-taglines'] span").content.strip.imdb_unescape_html rescue nil
    end

    # Returns a string containing the mpaa rating and reason for rating
    def mpaa_rating
      jsonld['contentRating']
    end

    # Returns a string containing the title
    def title(force_refresh = false)
      HTMLEntities.new.decode (jsonld['alternateName'] || jsonld['name'])
    end

    # Returns an integer containing the year (CCYY) the movie was released in.
    def year
      document.at("//h1[@data-testid = 'hero__pageTitle']//span[@data-testid = 'hero__primary-text-suffix']").text.gsub(/\D/,'').to_i rescue nil
    end

    # Returns release date for the movie.
    def release_date
      sanitize_release_date(document.at_css("a[@href$='ttrv_ov_rdat']").content) rescue nil
    end

    # Returns filming locations from imdb_url/locations
    def filming_locations
      locations_document.css("div[data-testid='item-id'] a[data-testid='item-text-with-link']").map { |link| link.content.strip } rescue []
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

    def jsonld
      @jsonld ||= JSON.parse(Nokogiri::HTML(Imdb::Movie.find_by_id(@id, "")).css('script[@type="application/ld+json"]').text)
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

    def synopsis_document
      @synopsis_document ||= Nokogiri::HTML(Imdb::Movie.find_by_id(@id, 'synopsis'))
    end
    
    # Use HTTParty to fetch the raw HTML for this movie.
    def self.find_by_id(imdb_id, page = :combined)
      #HTTPX.plugin(:follow_redirects).with(headers:{ "User-Agent" => "Chrome Probably" }).get("http://www.imdb.com/title/tt#{imdb_id}/#{page}")
      html = nil
      $browser_mutex.synchronize do
        page = $browser.create_page
        page.headers.set("User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36")
        page.go_to("https://www.imdb.com/title/tt#{imdb_id}/#{page}")
        sleep 2
        html = page.body
        if html[-1000..-1] =~ /Enable JavaScript and then reload the page./
          sleep 4
          html = page.body
        end
        $browser.reset
      end
      html
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
