require 'oga'
require 'net/http'
require 'net/ftp'
require 'uri'
require 'tempfile'

def open_and_parse(url, xml: false)
  uri     = URI.parse(url)
  content = Net::HTTP.get(uri).force_encoding('utf-8')
  xml ? Oga.parse_xml(content) : Oga.parse_html(content)
end

THREAD_COUNT = 10

html  = open_and_parse('https://www.morecore.de/rss.xml', xml: true)
items = html.xpath('//item')
queue = Queue.new
mutex = Mutex.new
items.each { |item| queue << item }

threads = Array.new(THREAD_COUNT) do
  Thread.new do
    loop do
      item = queue.pop(true) rescue break
      url = item.xpath('link').text
      puts url
      article_html = open_and_parse(url)
      content_html = article_html.xpath('//div[@class="article-prose"]').map(&:to_xml).compact.join('')
      content_encoded = Oga::XML::Element.new(name: 'content:encoded')
      cdata = Oga::XML::Cdata.new(text: content_html)
      content_encoded.children = Oga::XML::NodeSet.new([cdata])
      mutex.synchronize { item.children << content_encoded }
    end
  end
end
threads.each(&:join)

file = Tempfile.new('rss.xml')
file.write(html.to_xml)
file.close
Net::FTP.open(ENV['FTP_HOST'], ENV['FTP_USER'], ENV['FTP_PASS']) do |ftp|
  ftp.putbinaryfile(file, '/html/morecore/rss.xml')
end

puts 'Morecore erfolgreich aktualisiert'
