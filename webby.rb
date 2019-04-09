#!/usr/bin/ruby
#
require "sinatra"
require "erb"
require "yaml"
require "sqlite3"
require "date"

set :bind, '0.0.0.0'

def teamNums(confs)
  teamNumbers = Array.new()
  confs.each do |cf|
    conf = YAML.load_file("./conf.d/#{cf}")
    begin
	    db = SQLite3::Database.new(conf["settings"]["dbfile"])
	    rows = db.execute("select teamNumber from #{conf["settings"]["sport"]}_#{conf["settings"]["name"]}")
	    rows.each do |row|
	      teamNumbers.append row.first if !teamNumbers.include?(row.first)
	    end
    rescue
    end
  end
  return teamNumbers
end

get '/summary' do
  sort = params["sort"]
  sport = params["sport"]
  data = params["data"]
  out = '<html><body>'
  confList = Dir.entries("conf.d").select{|d| !File.directory? d}

  out += "<table><tr>"
  spl = Array.new
  confList.each do |cl|
    conf = YAML.load_file("./conf.d/#{cl}")
    spl.append(conf["settings"]["sport"]) if !spl.include?(conf["settings"]["sport"])
  end
  spl.each do |sp|
    out += "<td><a href='summary?sort=#{sort}&sport=#{sp}&data=#{data}'>#{sp}</a></td>"
  end
  out += "</tr></table>"

  out += "<table><tr><td><a href='summary?sort=#{sort}&sport=#{sport}&data=total'>Total</a></td><td><a href='summary?sort=#{sort}&sport=#{sport}&data=spread'>Spread</a></td><td><a href='summary?sort=#{sort}&sport=#{sport}&data=mline'>Money Line</a></td></tr></table>"


  out += '<table border="1">'
  out += '<tr>'
  out += "<td><a href='summary?sort=0&sport=#{sport}&data=#{data}'>Rot</a></td><td><a href='summary?sort=1&sport=#{sport}&data=#{data}'>Time</a></td>"

  confList.each do |cf|
    conf = YAML.load_file("./conf.d/#{cf}")
    if conf["settings"]["sport"] == sport
      out += "<td>#{conf["settings"]["name"]}</td>"
    end
  end
  out += '</tr>'
  tn = teamNums(confList)
  tr = Array.new()
  tn.each do |t|
    td = Array.new
    td.append(t)
    conf = YAML.load_file("./conf.d/#{confList.first}")
    dbName = "#{conf["settings"]["sport"]}_#{conf["settings"]["name"]}"
    time = ""
    begin
	    db = SQLite3::Database.new(conf["settings"]["dbfile"])
	    row = db.execute("select time from #{dbName} where teamNumber='#{t}'")
	    time = row.first.first if row.length > 0
    rescue
    end
    td.append(time)
    confList.each do |cf|
      conf = YAML.load_file("./conf.d/#{cf}")
      u = ""
      d = ""
      begin
	      dbName = "#{conf["settings"]["sport"]}_#{conf["settings"]["name"]}"
	      db = SQLite3::Database.new(conf["settings"]["dbfile"])
	      row = db.execute("select updated from #{dbName} where teamNumber='#{t}'")
	      u = row.first.first if row.length > 0
      rescue
      end
      if u != "" && Time.now() - Time.parse(u) < 1800
        row = db.execute("select #{data} from #{dbName} where teamNumber='#{t}'")
        d = row.first.first if row.length > 0
      end
      td.append(d)
    end
    tr.append(td)
  end
  tr.sort!{|a,b| a[sort.to_i] <=> b[sort.to_i]}
  tr.each do |t|
    out += "<tr>"
    t.each do |r|
      out += "<td>#{r}</td>"
    end
    out += "</tr>"
  end
  out += '</table></body></html>'
  out
end


