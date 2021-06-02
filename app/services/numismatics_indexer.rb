class NumismaticsIndexer
  attr_reader :solr_url
  def initialize(solr_url:)
    @solr_url = solr_url
  end

  def full_index
    solr = RSolr.connect(url: solr_url)
    solr_documents.each_slice(500) do |docs|
      solr.add(docs)
    end
    solr.commit
  end

  def solr_documents
    json_response = PaginatingJsonResponse.new(url: search_url)
    json_response.lazy.map do |json_record|
      json_record
    end
  end

  class NumismaticRecordPathBuilder
    attr_reader :result
    def initialize(result)
      @result = result
    end

    def path
      "https://figgy.princeton.edu/concern/numismatics/coins/#{id}/orangelight"
    end

    def id
      result["id"]
    end
  end

  class PaginatingJsonResponse
    include Enumerable
    attr_reader :url
    def initialize(url:)
      @url = url
    end

    def each
      response = Response.new(url: url, page: 1)
      loop do
        response.docs.each do |doc|
          yield json_for(doc)
        end
        break unless (response = response.next_page)
      end
    end

    def json_for(doc)
      JSON.parse(open(NumismaticRecordPathBuilder.new(doc).path).read)
    end

    def total
      @total ||= Response.new(url: url, page: 1).total_count
    end

    class Response
      require 'open-uri'
      attr_reader :url, :page
      def initialize(url:, page:)
        @url = url
        @page = page
      end

      def docs
        response["docs"]
      end

      def response
        @response ||= JSON.parse(open("#{url}&page=#{page}").read.force_encoding('UTF-8'))["response"]
      end

      def next_page
        return nil unless response["pages"]["next_page"]
        Response.new(url: url, page: response["pages"]["next_page"])
      end

      def total_count
        response["pages"]["total_count"]
      end
    end
  end

  def search_url
    "https://figgy.princeton.edu/catalog.json?f%5Bhuman_readable_type_ssim%5D%5B%5D=Coin&f%5Bstate_ssim%5D%5B%5D=complete&f%5Bvisibility_ssim%5D%5B%5D=open&per_page=100&q="
  end
end
