require 'uri'
filename = ARGV.first
File.open(filename) do |file|
  while line = file.gets
    if /^(#+) (.*)/ =~ line
      next if $1.size >= 3
      level = $1.size - 1
      headline = $2
      print " " * 2 * level
      puts "* [#{headline}](##{URI.escape(headline.downcase.tr(' ', '-').gsub('.', ''))})"
    end
  end
end
