require 'rss/maker'
require 'oga'
require 'time'
require 'net/http'
require 'net/ftp'
require 'uri'
require 'tempfile'
require 'base64'

BASE_URL     = 'https://www.morecore.de'
article_urls = []

def open_and_parse(url)
  uri     = URI.parse(url)
  content = Net::HTTP.get(uri).force_encoding('utf-8')
  Oga.parse_html(content)
end

9.times do |index|
  page       = index + 1
  is_home    = page == 1
  url        = is_home ? BASE_URL : "#{BASE_URL}/page/#{page}/"
  html       = open_and_parse(url)
  containers = html.xpath('//div[contains(@class, "infinite-post-morenews")]')

  if is_home
    featured_containers = html.xpath('//article[@class="newest_card" or @class="latestnews_card"]')
    containers          = featured_containers + containers
  end

  containers.each do |container|
    article_urls << container.xpath('descendant::a[contains(@class, "card_thumbnail")]').first.attr('href').value
  end
end

rss              = RSS::Maker::RSS20.new
feed             = rss.channel
feed.generator   = 'Ennofeed'
feed.link        = BASE_URL
feed.title       = 'MoreCore.de'
feed.description = 'Morecore Feed – parsed by Enno'

article_urls.each do |link|
  rss_item                  = rss.items.new_item
  rss_item.link             = link
  rss_item.guid.content     = link
  rss_item.guid.isPermaLink = true

  content  = open_and_parse(link)
  date_str = content.xpath('//meta[@property="article:published_time"]').first.attr('content').value

  rss_item.title       = content.xpath('//h1').text.strip
  rss_item.description = content.xpath('//p[@class="single-news_subtitle"]').first.children.first.text.strip
  rss_item.date        = DateTime.parse(date_str).to_time

  article_image_url = content.xpath('//meta[@property="og:image"]').first.attr('content').value
  html              = "<img src='#{article_image_url}' />"

  root_node = content.xpath('//div[contains(@class, "morecore-content")]').first ||
              content.xpath('//div[contains(@class, "mc_content-single")]').first

  root_node.children.each do |child|
    next unless child.is_a?(Oga::XML::Element)

    class_val = child.attr('class')&.value || ''

    break if class_val == 'swp-hidden-panel-wrap'

    child_html = if class_val.include?('BorlabsCookie')
                   encoded_html = child.xpath('div/script').first.children.first.to_xml
                   decoded_html = Base64.decode64(encoded_html)
                   Oga.parse_html(decoded_html).xpath('//iframe').first.to_xml
                 else
                   child.to_xml
                 end

    html += child_html
  end

  rss_item.content_encoded = html
end

file = Tempfile.new('rss.xml')
file.write(rss.to_feed.to_s)
file.close
Net::FTP.open(ENV['FTP_HOST'], ENV['FTP_USER'], ENV['FTP_PASS']) do |ftp|
  ftp.putbinaryfile(file, '/html/morecore/rss.xml')
end

puts 'Morecore erfolgreich aktualisiert'
