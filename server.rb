require 'sinatra'
require 'httparty'
require 'nokogiri'
require 'parallel'
require 'awesome_print'

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

  # write response
  response = {}
  response[:total_job_listings] = listing_urls.count
  response[:matched_listings] = listing_urls.keep_if{ |e| e[:matched_keywords].count > 0}.sort_by{|e| -e[:matched_keywords].count }
  content_type :json
  response.to_json
end

def match_job_posting_against_keywords(link, keywords)
  doc = HTTParty.get(link, limit: 20)
  matched_keywords = keywords.select {|k| doc.body.include?(k) }
end