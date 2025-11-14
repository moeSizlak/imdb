module Imdb
  # Search IMDB for a title
  class Search < MovieList
    attr_reader :query

    # Initialize a new IMDB search with the specified query
    #
    #   search = Imdb::Search.new("Star Trek")
    #
    # Imdb::Search is lazy loading, meaning that unless you access the +movies+
    # attribute, no query is made to IMDB.com.
    #
    def initialize(query)
      @query = query
    end

    # Returns an array of Imdb::Movie objects for easy search result yielded.
    # If the +query+ was an exact match, a single element array will be returned.
    def movies
      @movies ||= (exact_match? ? parse_movie : parse_movies)
    end

    private

    def document
      @document ||= Nokogiri::HTML(Imdb::Search.query(@query))
    end

    def self.query(query)
      #HTTPX.plugin(:follow_redirects).with(headers:{ "User-Agent" => "Chrome Probably; Also, I banged your mom." }).get("http://www.imdb.com/find/?q=#{CGI.escape(query)}")
      html = nil
      $browser_mutex.synchronize do
        page = $browser.create_page
        page.headers.set("User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36")
        page.go_to("http://www.imdb.com/find/?q=#{CGI.escape(query)}")
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

    def parse_movie
      id    = document.at("head/link[@rel='canonical']")['href'][/\d+/]
      title = document.at('h1').inner_html.split('<span').first.strip.imdb_unescape_html

      [Imdb::Movie.new(id, title)]
    end

    # Returns true if the search yielded only one result, an exact match
    def exact_match?
      !document.at("table[@id='title-overview-widget-layout']").nil?
    end
  end # Search
end # Imdb
