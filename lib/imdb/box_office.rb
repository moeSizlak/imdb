module Imdb
  class BoxOffice < MovieList
    private

    def document
      @document ||= Nokogiri::HTML(URI.open('http://www.imdb.com/boxoffice/', "User-Agent" => "Chrome Probably"))
    end
  end # BoxOffice
end # Imdb
