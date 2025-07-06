module Imdb
  class Top250 < MovieList
    private

    def document
      #@document ||= Nokogiri::HTML(URI.open('http://www.imdb.com/chart/top'))
      @document ||= Nokogiri::HTML(HTTPX.plugin(:follow_redirects).get('http://www.imdb.com/chart/top'))
    end
  end # Top250
end # Imdb
