# Usage:
# ruby crawl.rb [remote path] [is mobile version?]
# Sample
# ruby crawl.rb ***.org 1

require 'rubygems'
require 'mechanize'
require 'uri'

def keys_to_sym src
  if src.is_a? Array
    src.map {|item| keys_to_sym item}
  elsif src.is_a? Hash
    Hash[src.map {|k, v| ["#{k}".to_sym, keys_to_sym(v)]}]
  else
    src
  end
end
def keys_to_str src
  if src.is_a? Array
    src.map {|item| keys_to_str item}
  elsif src.is_a? Hash
    Hash[src.map {|k, v| [k.to_s, keys_to_str(v)]}]
  else
    src
  end
end
def get_hash_file filename
  if File.exist?(filename)
    keys_to_sym YAML.load_file(filename)
  else
    nil
  end
end
def put_hash_file filename, props
  File.open(filename, 'w') do |f|
    f.write((keys_to_str props).to_yaml)
  end
end

def put_error url, error = nil
  @errors << url
  File.open("#{@host.gsub('http://', '')}.log", 'a+') do |file|
    file.write("#{[url, error].join("\t")}\n")
  end
end

def find_url uri
  s, h, p, q = uri.scheme, uri.host, uri.path
  if !s || s == 'https'
    ( h ? @outer_list : @link_list ).find {|link| link if (link[:path]==(p || ''))}
  else
    nil
  end
end

def add_url_to_list url
  u = URI(url)
  s, h, p, q, f = u.scheme, u.host, u.path, u.query, u.fragment
  if !s || s == 'https'
    link = find_url(u)
    if link
      link[:query] << q unless link[:query].include?(q)
    else
      ( h ? @outer_list : @link_list ) << {path: (p || ""), query: [q], host: h}
    end
    if !s && !h
      l = [@host, [p, q].join('?').chomp('?')].join('/').gsub(/([^:]|^)\/{2,}/, '\1/')
      @urls_to_check << l if !(@urls_to_check + @urls_checked).find {|item| item == l}
    end
  end
end

def check_images page
  page.images.each do |img|
    next if @errors.include?(img.src)
    begin
      data = @mech.get(img)
    rescue => e
      puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{img.src}"
      put_error img.src, e.methods.include?(:response_code) ? e.response_code : e.to_s
    end
  end
end

def check_assets page
  # pp page.images
  css = page.search('link[rel="stylesheet"]')
  css.each do |link|
    # pp link.attribute('href').value
    # src = URI(link.attribute('href').value) unless src.host
    h, p = page.uri.host, page.uri.path
    l = link.attribute('href').value
    l = [p, l].join('/') unless l =~ /^((http(s)?:)?\/(\/)?)/i
    l = ['http://',h , l].join() unless l =~ /^(http(s)?:)?\/\//i

    next if @urls_checked.include?(l) || @errors.include?(l)
    data = nil
    begin
      data = @mech.get(l).content
    rescue => e
      puts e
      puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{l}"
      put_error l, e.methods.include?(:response_code) ? e.response_code : e.to_s
    end

    data.scan(/url\s*\(\s*([^\)]+)\s*\)/mi).each do |l|
      _link = l[0].gsub(/(^\u0022|\u0022$)/, '')
      next if @errors.include?(_link)
      begin
        data = @mech.get _link
      rescue => e
        puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{_link}"
        put_error _link, e.methods.include?(:response_code) ? e.response_code : e.to_s
      end
    end

    @urls_checked << l
  end
end

def check_url url
  unless @urls_checked.include?(url) || @errors.include?(url)
    begin
      @mech.get(url) do |page|
        page.links.each do |link|
          begin
            _href = link.href.gsub(/([^:]|^)\/{2,}/, '\1/')
            u = URI(_href)
            add_url_to_list _href
          rescue => e
            puts "- err -> #{e.to_s}"
          end
        end
        check_assets page
        check_images page
      end
    rescue => e
      puts "#{e.methods.include?(:response_code) ? e.response_code : e.to_s} on #{url}"
      put_error url, e.methods.include?(:response_code) ? e.response_code : e.to_s
    end
  end
  if @urls_to_check.include?(url)
    @urls_checked << @urls_to_check.delete(url)
  end
end

def check_host host
  system "rm #{host.gsub('http://', '')}.log"
  puts "Scanning host: #{host}"
  @host = host
  @mobile = @config[:mobile] || @args[1]
  @mech = Mechanize.new { |agent|
    agent.follow_meta_refresh = true
    agent.add_auth(host, @config[:auth][:user], @config[:auth][:pass]) if @config[:auth]
    agent.user_agent_alias = "iPhone" if @mobile
  }

  @link_list = []
  @outer_list = []
  @urls_checked = []
  @urls_to_check = []
  @errors = []

  # check_url host
  @urls_to_check << host
  while @urls_to_check.size > 0
    curr = @urls_to_check[0]
    puts "[#{@urls_checked.size}/#{@urls_to_check.size}] Checking url #{curr}"
    check_url curr
  end
end

@host=""
def check_host_list list
  puts "Scanning list of hosts, total: #{list.size}"
  list.each do |host|
    check_host "http://#{host.gsub(/^(((http(s)?:)?\/\/)?)/i, '')}"
  end
end

puts puts '*'*25
@args = ARGV
@config = get_hash_file 'config.yml'
if @config
  puts "Settings:"
  pp @config
end

if @args[0] =~ /^list$/i
  puts '*'*25
  puts 'Scnning list:'
  pp @config[:list]
  check_host_list @config[:list]
else
  @host = "http://#{@args[0].gsub(/^(((http(s)?:)?\/\/)?)/i, '')}"
  check_host @host
end
puts '*'*25

pp @errors
