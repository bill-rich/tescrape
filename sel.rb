#!/usr/bin/ruby

require "selenium-webdriver"
require "json"
require "nokogiri"
require "yaml"
require "sqlite3"
require "open-uri"
require "time"

def parseCookies(site) 
  if !File.exist?(site+".txt") 
    return []
  end
  cf = File.read(site+".txt")
  js = JSON.parse(cf)
  return js
  js = js.inject({}){ |cookie, i| 
    i.inject({}){ |c, (k,v)| 
      k = k.to_sym
      cookie[k.to_sym] = v
      cookie
    }
  }
  puts js
  return js
end

def storeCookies(conf, cookies)
  site = conf["site"]["site"]
  cj = JSON.generate(cookies)
  c = File.open(site+".txt", "w")
  c.puts cj
  c.close
end

def loginSite(driver, conf)
  #LOGIN
  sleep 1
  begin
    usr = driver.find_element name: conf["nav"]["user"]
    pass = driver.find_element name: conf["nav"]["pass"]
    usr.send_keys(conf["site"]["user"])
    pass.send_keys(conf["site"]["pass"])
    if conf["nav"]["submit"] != nil
      submit = driver.find_element name: conf["nav"]["submit"]
      submit.click
    else
      pass.submit()
    end
  rescue
    puts "[DEBUG] Session still active"
  end
end

def navigateSite(driver, conf)
  conf["nav"]["order"].each do |step|
    driver.manage.window.resize_to(conf["settings"]["windowW"],conf["settings"]["windowH"])
    driver.save_screenshot("/tmp/#{step.keys.first}_#{step.values.first}.png")
    case step.keys.first
    when "direct"
      site = conf["site"]["site"]
      path = conf["site"]["path"]
      driver.navigate.to("http://"+site+path)
    when "id"
      x = driver.find_element id: step.values.first
      x.click
    when "name"
      x = driver.find_element name: step.values.first
      x.click
    when "sleep"
      sleep step.values.first
    end
  end
end

def screenshotSite(driver, conf)
  driver.manage.window.resize_to(conf["settings"]["windowW"],conf["settings"]["windowH"])
  driver.execute_script(conf["ocr"]["script"])
  sleep 1
  driver.save_screenshot(conf["settings"]["siteimg"])
end

def prepareBrowser(conf)
  site = conf["site"]["site"]
  path = conf["site"]["path"]
  options = Selenium::WebDriver::Firefox::Options.new
  #options.headless!
  #options = Selenium::WebDriver::Chrome::Options.new
  #options.add_argument('--proxy-server=127.0.0.1:8080')
  #options.add_argument('--headless')
  #driver = Selenium::WebDriver.for :chrome, options: options
  #profile = Selenium::WebDriver::Firefox::Profile.new
  #profile = Selenium::WebDriver::Firefox::Profile.from_name "/home/bruce/.mozilla/firefox/zlyd45yw.default"
  profile = Selenium::WebDriver::Firefox::Profile.from_name "selenium"
  profile["network.proxy.type"] = 1
  profile["network.proxy.http"] = "127.0.0.1"
  profile["network.proxy.http_port"] = 8080
  profile["extensions.webcompat.onByDefault"] = true

  driver = Selenium::WebDriver.for(:firefox, :profile => profile, :options => options)
  
  #driver = Selenium::WebDriver.for :firefox
  driver.navigate.to("http://"+site+path)
  #cookies = parseCookies(site)
  #cookies.each do |cookie|
  #  cookie = cookie.inject({}){|cookie,(k,v)| cookie[k.to_sym] = v; cookie}
  #  begin
  #    cookie[:expires] = DateTime.parse(cookie[:expires])
  #  rescue
  #    puts "[DEBUG] Looks like the cookie #{cookie[:name]} doesn't expire"
  #  end
  #  puts cookie
  #  driver.manage.add_cookie(cookie)
  #end
  driver.navigate.to("http://"+site+path)
  return driver
end

def shootSite(conf)
  driver = prepareBrowser(conf)
  loginSite(driver, conf)
  sleep 5
  navigateSite(driver, conf)
  screenshotSite(driver, conf)
  storeCookies(conf, driver.manage.all_cookies)
  driver.quit
end

class Word
  @xs = 0
  @ys = 0
  @xe = 0
  @ye = 0
  @conf = 0
  @word = ""

  def initialize(iword, ixs, iys, ixe, iye, conf)
    @word = iword
    @xs = ixs.to_i
    @ys = iys.to_i
    @xe = ixe.to_i
    @ye = iye.to_i
    @conf = conf.to_i
  end

  def xs()
    return @xs
  end
  def ys()
    return @ys
  end
  def xe()
    return @xe
  end
  def ye()
    return @ye
  end
  def word()
    return @word
  end
  def conf()
    return @conf
  end
  def updateWord(word)
    @word = word
  end
end

def runOpenOCR(outfile, siteimg)
  #`tesseract #{siteimg} #{outfile} --psm 12 --oem 1 hocr`
  #`TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/tessdata/ tesseract #{siteimg} #{outfile} -l osd --psm 12 --oem 0 configfile2 hocr`
  `TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/ /home/bill/tesseract-4.0.0/build/bin/tesseract #{siteimg} #{outfile} --psm 12 --oem 0 configfile2`
  #`tesseract #{siteimg} #{outfile} --psm 12 --oem 1 hocr &> /dev/null`
  #`tesseract /tmp/site.png #{outfile} --psm 12 --oem 0 --dpi 300 configfile hocr`
end

def runNumOCR(outfile, siteimg)
  `TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/ /home/bill/tesseract-4.0.0/build/bin/tesseract #{siteimg} #{outfile} --psm 8 --oem 0 configfile &> /dev/null`
end

def processWords(infile)
  hocr = File.read("#{infile}.hocr")
  doc = Nokogiri::XML(hocr)
  words = doc.css("span").select{|s| s["class"] == "ocrx_word"}
  wl = Array.new
  words.each do |word|
    match = /^bbox\s([0-9]+)\s([0-9]+)\s([0-9]+)\s([0-9]+);\sx_wconf\s([0-9]+)/.match(word["title"])
    xs, ys, xe, ye, conf = match.captures
    w = Word.new(word.text, xs, ys, xe, ye, conf)
    wl.append(w)
  end
  return wl
end

def cropImage(w, src, tmpimg) 
  buffer = 5
  `convert #{src} -crop #{w.xe-w.xs+buffer*2}x#{w.ye-w.ys+buffer*2}+#{w.xs-buffer}+#{w.ys-buffer} #{tmpimg}`
end

def tp(objects, *method_names)
  terminal_width = `tput cols`.to_i
  cols = objects.count + 1 # Label column
  col_width = (terminal_width / cols) - 1 # Column spacing

  Array(method_names).map do |method_name|
    cells = objects.map{ |o| o.send(method_name).inspect }
    cells.unshift(method_name)

    puts cells.map{ |cell| cell.to_s.ljust(col_width) }.join ' '
  end

  nil
end

def findTeamNumX(wl, teamNumbers, conf)
  confidence = conf["ocr"]["confidence"]
  toleranceX = conf["ocr"]["toleranceX"]
  teamX = 0
  wl.each do |w|
    if w.word =~ /^[0-9]{3,5}$/ && w.conf > confidence && teamNumbers.include?(w.word.to_i)
      break unless wl.each do |w2|
        if w2.word != w.word && w2.word =~ /^[0-9]{3,5}$/ && (w.xs- w2.xs).abs < toleranceX && w2.conf > confidence && teamNumbers.include?(w.word.to_i)
          teamX = w2.xs
          break
        end
      end
    end
  end
  return teamX
end

def getRows(wl, teamX, teamNumbers, conf)
  toleranceX = conf["ocr"]["toleranceX"]
  toleranceY = conf["ocr"]["toleranceY"]
  rows = Array.new
  wl.each do |w|
    #`convert /tmp/site.png -fill none -stroke red -strokewidth 3 -draw "rectangle #{w.xs},#{w.ys} #{w.xe},#{w.ye}" /tmp/site.png`
    if (w.xs - teamX).abs < toleranceX && teamNumbers.include?(w.word.to_i)
      row = Array.new
      wl.each do |w3|
        if (w3.ys - w.ys).abs < toleranceY
          cropImage(w3, conf["settings"]["siteimg"], conf["settings"]["tmpimg"])
          runNumOCR(conf["settings"]["outfile"], conf["settings"]["tmpimg"])
          nw = processWords(conf["settings"]["outfile"])
          if nw.length > 0
            new = nw.first.word

	    new.gsub!(/%/, ".5")
            new.gsub!(/^0/, "o")
            new.gsub!(/1\/2/, ".5")
            new.gsub!(/(?<=.)o/, "0")

            w3.updateWord(nw.first.word)
            row.append(w3)
          end
        end
      end
      rows.append(row)
    end
  end
  return rows
end

def getRowTemplate(rows, conf)
  toleranceX = conf["ocr"]["toleranceX"]
  rowTemplate = Array.new
  rows.each do |row|
    row.each do |c|
      if not rowTemplate.any?{|rt| (rt - c.xs).abs < toleranceX}
        rowTemplate.append(c.xs)
      end
    end
  end
  rowTemplate.sort!
  return rowTemplate
end

def alignRows(rows, rowTemplate, conf)
  toleranceX = conf["ocr"]["toleranceX"]
  newRows = Array.new()
  rows.each do |row|
    nr = Array.new(rowTemplate.length) { |i| i = Word.new("nil",0,0,0,0,0)}
    row.each do |c|
      rowTemplate.each_with_index do |v,i|
        if (c.xs - v).abs < toleranceX
          nr[i] = c
        end
      end
    end
    newRows.append(nr)
  end
  return newRows
end

def breakCombinedRows(rows, teamNumbers)
  newRows = Array.new()
  rows.each do |row|
    broke = false
    row.each_with_index do |cell, i|
      if teamNumbers.include?(cell.word.to_i) && i > 0
        newRows.append(row[0..i-1])
	newRows.append(row[i..row.length-1])
        broke = true
        break
      end
    end
    newRows.append(row) if not broke
  end
  return newRows
end

def printRows(rows)
  rows.each do |row|
    row.each do |w|
      #print "#{w.word}(#{w.xs},#{w.ys})\t"
      print "#{w.word},"
    end
    print "\n"
  end
end


def ocrSite(conf)
  numdates = getNumDate(conf)
  teamNumbers = Array.new
  numdates.each do |numdate|
    teamNumbers.append(numdate[0])
    teamNumbers.append(numdate[1])
  end
  runOpenOCR(conf["settings"]["outfile"], conf["settings"]["siteimg"])
  wl = processWords(conf["settings"]["outfile"])
  pp wl
  teamX = findTeamNumX(wl, teamNumbers, conf)
  rows = getRows(wl, teamX, teamNumbers, conf)
  rowTemplate = getRowTemplate(rows, conf)
  rows = alignRows(rows, rowTemplate, conf)
  rows = breakCombinedRows(rows, teamNumbers)
  rows.sort_by!{|r| r.first.word.to_i} 
  db = openDB(conf)
  createTable(db, conf)
  writeRows(db, rows, numdates, conf)
  printRows(rows)
end

def openDB(conf)
  db = SQLite3::Database.new(conf["settings"]["dbfile"])
  return db
end

def writeRows(db, rows, numdate, conf)
  layout = conf["layout"]
  rows.each do |row|
    teamNumber = ""
    d = numdate.select{|n| n[0] == row[layout["teamnumber"].first].word.to_i || n[1] == row[layout["teamnumber"].first].word.to_i}
    next if d.length == 0
    date = d.first[2]
    time = d.first[3]
    datetime = Time.parse("#{Time.now.year}/#{date} #{time}")
    layout["teamnumber"].each do |i|
      teamNumber = "#{teamNumber}#{row[i].word}"
    end
    spread = ""
    layout["spread"].each do |i|
      spread = "#{spread}#{row[i].word}"
    end
    total = ""
    layout["total"].each do |i|
      total = "#{total}#{row[i].word}"
    end
    mline = ""
    layout["mline"].each do |i|
      mline = "#{mline}#{row[i].word}"
    end
    dbr = db.execute("select * from #{conf["settings"]["sport"]}_#{conf["settings"]["name"]} where teamNumber == '#{teamNumber}'")
    if dbr.length > 0
      db.execute("update #{conf["settings"]["sport"]}_#{conf["settings"]["name"]} set time='#{datetime.to_s}',  spread='#{spread}', total='#{total}', mline='#{mline}', updated='#{Time.now.to_s}' where teamNumber='#{teamNumber}';")
    else
      db.execute("insert into #{conf["settings"]["sport"]}_#{conf["settings"]["name"]} values ('#{teamNumber}', '#{datetime.to_s}',  '#{spread}', '#{total}', '#{mline}', '#{Time.now.to_s}');")
    end
  end
end

def createTable(db, conf)
  begin
    rows = db.execute ("create table #{conf["settings"]["sport"]}_#{conf["settings"]["name"]} (teamNumber int, time DateTime, spread varchar(30), total varchar(30), mline varchar(30), updated DateTime);")
  rescue
    puts "[DEBUG] Table already exists"
  end
end

def dropTable(conf)
  begin
    db.execute ("DROP TABLE #{conf["settings"]["sport"]}_#{conf["settings"]["name"]};")
  rescue
    puts "[DEBUG] Table not found"
  end
end

def getNumDate(conf)
  page = open("http://www.vegasinsider.com/#{conf["settings"]["numDateSource"]}/odds/las-vegas/")
  doc = Nokogiri::HTML(page.read)
  games1 = doc.xpath('//td[@class = "viCellBg1 cellTextNorm cellBorderL1"]')
  games2 = doc.xpath('//td[@class = "viCellBg2 cellTextNorm cellBorderL1"]')
  games = games1 + games2
  numdates = Array.new
  games.each do |game|
    td = game.text.match(/([0-9]{1,2}\/[0-9]{1,2})\s+([0-9]{1,2}:[0-9]{2}\s[AP]M)/)
    date, time = td.to_s
    n = game.text.scan(/\b([0-9]{3,})\b/)
    n1 = n.first.first.to_i
    n2 = n.last.first.to_i
    numdates.append([n1, n2, date, time])
  end
  return numdates
end

confList = Dir.entries("conf.d").select{|d| !File.directory? d}
confList.each do |cf|
  begin
    conf = YAML.load_file("./conf.d/#{cf}")
    shootSite(conf)
    ocrSite(conf)
  rescue => e
	  puts e
	  p e.backtrace
  end
end
