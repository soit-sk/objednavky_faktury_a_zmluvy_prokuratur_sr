require 'rubygems'
require 'scraperwiki'
require 'nokogiri'
require 'open-uri'

require 'pp'

class Dummy
  def text
    ''
  end
end

def parse_it(doc, table, institution)
  doc.xpath('//table[@class="tab-kontakt"]/tr').each do |tr|
    next if tr.xpath('.//td[@class="pozadie-okrove1"]').children.size != 0
    next if tr.xpath('.//td/h3').children.size != 0
    tds = tr.xpath('.//td')

    case table
    when /objednavky/u then
      data = {
          "evid_cislo"  => (tds[0].text.strip),
          "date"        => (tds[1].text.strip),
          "supplier"    => (tds[2].text.strip),
          "subject"     => ((tds[3].xpath('.//div[@class="objednavky-predmet"]') || Dummy.new).text.strip),
          "buyer"       => ((tds[3].xpath('.//div[@class="objednavky-objednavatel"]') || Dummy.new).text.strip),
          "price"       => ((tds[4] || Dummy.new).text.strip),
          "institution" => institution}
    when /faktury/u then
      data = {
          "evid_cislo"     => (tds[0].text.strip),
          "delivery_date"  => (tds[1].text.strip),
          "payment_date"   => (tds[2].text.strip),
          "supplier"       => (tds[3].text.strip),
          "subject"        => ((tds[4].xpath('.//div[@class="faktury-predmet"]') || Dummy.new).text.strip),
          "contract"       => ((tds[4].xpath('.//div[@class="faktury-zmluva"]') || Dummy.new).text.strip),
          "purchase"       => ((tds[4].xpath('.//div[@class="faktury-objednavka"]') || Dummy.new).text.strip),
          "price"          => ((tds[5] || Dummy.new).text.strip),
          "institution"    => institution}
    when /zmluvy/u then
      data = {
          "evid_cislo"     => (tds[0].text.strip),
          "publication_date"  => (tds[1].text.strip),
          "contract_date"  => (tds[2].text.strip),
          "supplier"       => (tds[3].text.strip),
          "subject"        => (tds[4].text.strip),
          "price"          => ((tds[5] || Dummy.new).text.strip),
          "institution"    => institution}
    end

    ScraperWiki.save_sqlite(unique_keys = ["evid_cislo", "institution"], data = data, table_name = table)
  end
end

def parse_zsnh(doc, institution)
  doc.xpath('//div[@class="content"]/table[@class="tab-kontakt"]/tbody/tr').each do |tr|
    next if tr.xpath('.//td[@class="pozadie-okrove1"]').children.size != 0
    next if tr.xpath('.//td/h3').children.size != 0
    tds = tr.xpath('.//td')
    next if tds.size == 0

    data = {
        "por_cislo"   => (tds[0].text.strip),
        "supplier"    => ((tds[1] || Dummy.new).text.strip),
        "subject"     => ((tds[2] || Dummy.new).text.strip),
        "price"       => ((tds[3] || Dummy.new).text.strip),
        "institution" => institution}
    ScraperWiki.save_sqlite(unique_keys = ["por_cislo", "institution"], data = data, table_name = 'zsnh')
  end
end

def parse_elektr_aukcie(doc, institution)
  doc.xpath('//table[@class="tab-kontakt"]/tr').each do |tr|
    next if tr.xpath('.//td[@class="pozadie-okrove1"]').children.size != 0
    next if tr.xpath('.//td/h3').children.size != 0 #h3[@class="pozadie-okrove1"]').children.size != 0
    tds = tr.xpath('.//td')

    data = {
        "por_cislo"   => (tds[0].text.strip),
        "date"        => (tds[1].text.strip),
        "supplier"    => (tds[2].text.strip),
        "subject"     => (tds[3].text.strip),
        "price_before" => ((tds[4] || Dummy.new).text.strip),
        "price_after"  => ((tds[5] || Dummy.new).text.strip),
        "institution"  => institution
    }
    ScraperWiki.save_sqlite(unique_keys = ["por_cislo", "institution"], data = data, table_name = "elaukcie")
  end
end

SITE = 'https://www.genpro.gov.sk'
url = "https://www.genpro.gov.sk/objednavky-faktury-a-zmluvy-28dd.html"
doc = Nokogiri::HTML(open(url, :read_timeout => 300))

navig = doc.xpath('//ul[@class="navigacia"]/li/a')
navig.each do |nav|
  institution = nav.text

  if /str.nka .radu.*/u =~ institution
    next
  end

  html = open(SITE + nav['href'], :read_timeout => 300)
  doc = Nokogiri::HTML(html)
  doc.xpath('//li[@class="activ"]/ul/li/a').each do |lnk_node|
    htm = open(SITE + lnk_node['href'], :read_timeout => 300)
    doc  = Nokogiri::HTML(htm)

    case lnk_node
    when /objedn\303\241vky/u then
      divs = doc.xpath('//ul[@id="list-years"]/li/div')
      divs.each do |div|
        months = div.xpath('.//a')
        months.each do |month|
          doc = Nokogiri::HTML(open(SITE + lnk_node['href'] + month['href'], :read_timeout => 300))
          parse_it(doc, "objednavky", institution)
        end
      end
    when /fakt\303\272ry/u then
      divs = doc.xpath('//ul[@id="list-years"]/li/div')
      divs.each do |div|
        months = div.xpath('.//a')
        months.each do |month|
          doc = Nokogiri::HTML(open(SITE + lnk_node['href'] + month['href'], :read_timeout => 300))
          parse_it(doc, "faktury", institution)
        end
      end
    when /zmluvy/u then
      divs = doc.xpath('//ul[@id="list-years"]/li/div')
      divs.each do |div|
        months = div.xpath('.//a')
        months.each do |month|
          doc = Nokogiri::HTML(open(SITE + lnk_node['href'] + month['href'], :read_timeout => 300))
          parse_it(doc, "zmluvy", institution)
        end
      end
    when /z\303\241kazky s n\303\255zkou hodnotou/u then
      parse_zsnh(doc, institution)
    when /elektronick\303\251 aukcie/u then
      doc.xpath('//div[@class="content"]/div/span/a').each do |a|
        doc = Nokogiri::HTML(open(SITE + lnk_node['href'] + a['href'], :read_timeout => 300))
        parse_elektr_aukcie(doc, institution)
      end
    end
  end

end
