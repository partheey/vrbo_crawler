require 'selenium-webdriver'
require 'nokogiri'
require 'csv'
require 'securerandom'

def setup_driver
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--user-agent=' + random_user_agent)
  driver = Selenium::WebDriver.for :chrome, options: options
  driver.manage.window.maximize
  driver
end

def random_user_agent
  [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15'
  ].sample
end

def get_listings(driver, startDate=Date.today)
  listings = []
  
  address = 'Chicago 63rd Street Station, Chicago, Illinois, United States of America'
  url = "https://www.vrbo.com/search?destination=#{address}&startDate=#{startDate.to_s}&endDate=#{(startDate+1).to_s}"
  driver.get(url)
  sleep rand(5..10)
  
  3.times do
    current_height = driver.execute_script('document.querySelector(".uitk-scrollable.uitk-scrollable-vertical").scrollTo(0, 3531)')
    driver.execute_script("window.scrollTo(0, #{current_height});")
    sleep rand(5..10)
  end
  
  doc = Nokogiri::HTML(driver.page_source)
  
  doc.css('[data-stid="property-listing-results"]').each do |listing|
    p_title = listing.css('[data-stid="open-hotel-information"]').text.gsub('More information about ', '').gsub(', opens in a new tab', '')
    p_url = listing.css('[data-stid="open-hotel-information"]').attr('href')
    listing_data = {
      title: p_title,
      url: p_url,
      price: listing.css('[data-test-id="price-summary-message-line"]').children.last.text
    }
    listings << listing_data
    break if listings.size >= 50
  end
  
  listings
end

# def get_nightly_prices(driver, listing_url)
#   prices = []
#   driver.get(listing_url)
#   sleep rand(5..10)
  
#   human_interaction(driver)
#   driver.execute_script('window.scrollTo(0, document.body.scrollHeight / 2);')
#   sleep rand(2..5)
#   driver.execute_script('window.scrollTo(0, document.body.scrollHeight);')
#   sleep rand(2..5)
  
#   doc = Nokogiri::HTML(driver.page_source)
  
#   doc.css('.price-calendar').each do |calendar|
#     calendar.css('.price').each do |price|
#       prices << {
#         date: price.css('.date').text.strip,
#         amount: price.css('.amount').text.strip
#       }
#     end
#   end
  
#   prices
# end

def human_interaction(driver)
  driver.execute_script("window.scrollBy(0, #{rand(100..300)});")
  sleep rand(1..3)
  driver.execute_script("window.scrollBy(0, -#{rand(100..300)});")
  sleep rand(1..3)
end

def save_to_csv(data, filename)
  CSV.open(filename, 'w') do |csv|
    csv << ['Title', 'URL', 'Date', 'Price']
    data.each do |listing|
      listing[:prices].each do |price|
        csv << [listing[:title], listing[:url], price[:date], price[:amount]]
      end
    end
  end
end

def retry_on_rate_limit
  retries = 0
  begin
    yield
  rescue Selenium::WebDriver::Error::WebDriverError => e
    if e.message.include?("429")
      retries += 1
      if retries <= 5
        sleep_time = 2**retries + rand(0..5)
        sleep sleep_time
        retry
      else
        raise "Max retries reached. Exiting."
      end
    else
      raise e
    end
  end
end

driver = setup_driver
listings = []

retry_on_rate_limit do
  listings = get_listings(driver)
end

listings.each do |listing|
  retry_on_rate_limit do
    listing[:prices] = get_nightly_prices(driver, listing[:url])
  end
end

save_to_csv(listings, 'vrbo_listings.csv')

driver.quit
