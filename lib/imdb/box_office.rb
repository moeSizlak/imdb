module Imdb
  class BoxOffice < MovieList
    private

    def document
      #@document ||= Nokogiri::HTML(URI.open('http://www.imdb.com/boxoffice/', "User-Agent" => "Chrome Probably"))
      @document ||= Nokogiri::HTML(HTTPX.plugin(:follow_redirects).with(headers:{ "User-Agent" => "Chrome Probably" }).get('http://www.imdb.com/boxoffice/'))
    end
  end # BoxOffice
end # Imdb
