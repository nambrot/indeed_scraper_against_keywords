require 'sinatra'
require 'httparty'
require 'nokogiri'
require 'parallel'
require 'awesome_print'
require 'csv'

get '/' do
  erb :index
end

get '/listings' do
  company = params[:company]
  keywords = params[:keywords].split(',').map(&:strip)
  
  # first indeed scrape
  doc = Nokogiri::HTML(HTTParty.get("http://www.indeed.com/cmp/#{URI.escape(company)}/jobs"))
  page = 1
  listing_urls = doc.css('#company_full_job_list ul li a').map { |e| { link: ("http://www.indeed.com" + e.attributes['href'].value), title: e.text } }
  total_pages = doc.css('#page_nav_info').text.split(' ').last.to_i

  # grab remaining pages
  while page < total_pages
    page += 1
    doc = Nokogiri::HTML(HTTParty.get("http://www.indeed.com/cmp/#{URI.escape(company)}/jobs?p=#{page}"))
    listing_urls += doc.css('#company_full_job_list ul li a').map { |e| { link: ("http://www.indeed.com" + e.attributes['href'].value), title: e.text } }
  end
  
  # ap "Found a total of #{listing_urls.count} listings"
  #match against keywords
  listing_urls = Parallel.map(listing_urls, :in_threads=>50){|e|
    {
      title: e[:title],
      link: e[:link],
      matched_keywords: match_job_posting_against_keywords(e[:link], keywords) 
    }  
  }

  listing_urls.keep_if{ |e| e[:matched_keywords].count > 0}

  #exclude keywords that appear in every single matched listing
  keywords_that_appear_in_all = keywords.zip(listing_urls.map{ |url| keywords.map { |k| url[:matched_keywords].include?(k) } }.transpose.map { |array_of_inclusions| array_of_inclusions.all? }).keep_if{|k| k.last}.map(&:first)
  listing_urls.map!{|e| e[:matched_keywords].reject!{|keyword| keywords_that_appear_in_all.include?(keyword)}; e; } 

  listing_urls.keep_if{ |e| e[:matched_keywords].count > 0}

  # write response
  response = {}
  response[:total_job_listings] = listing_urls.count
  response[:matched_listings] = listing_urls.sort_by{|e| -e[:matched_keywords].count }
  content_type :json
  response.to_json
end

get '/companies_hiring' do
  location = params[:location]
  keywords = params[:keywords]
  exclude_companies = CSV.parse(params[:exclude_companies]).first || []
  companies = []
  
  doc = Nokogiri::HTML(HTTParty.get("http://www.indeed.com/jobs?q=#{URI.escape(keywords)}&l=#{URI.escape(location)}"))
  companies += doc.css('#resultsCol .row .company span').map(&:text)
  next_link = doc.css('.pagination a:last')
  while next_link.text.match "Next"
    url = "http://www.indeed.com/" + next_link.first.attributes["href"].value
    doc = Nokogiri::HTML(HTTParty.get(url))
    companies += doc.css('#resultsCol .row .company span').map(&:text)
    next_link = doc.css('.pagination a:last')
  end

  companies.uniq!
  companies -= exclude_companies
  content_type :json
  companies.to_json
end

def match_job_posting_against_keywords(link, keywords)
  doc = Nokogiri::HTML(HTTParty.get(link, limit: 50)).css('body').inner_text
  matched_keywords = keywords.select {|k| doc.include?(k) }
  matched_keywords
end