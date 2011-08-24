#!/usr/bin/env ruby -Ku

if ARGV.length < 2

  puts '#################################################################'
  puts 'Usage ruby performance.rb <Username> <Password> <Number of tasks>'
  puts 'Default task number is 10000'
  puts '#################################################################'
  exit
else
  @username = ARGV[0]
  @password = ARGV[1]
  TIMES = ARGV[2].to_i ||= 10000
end

#standard libs
require 'rubygems'
require 'fileutils'
require 'logger'
require 'benchmark'


#test data
require 'addressable/uri'
require 'faker'

#ActiveRecord
require 'active_record'




#use local dm core file if exist, comes from the original script in dm core
path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'dm-core'))
if File.exists? path
  require path
else
  require 'dm-core'
end
#require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'dm-core')) ||='dm-core'

#DataMapper
require 'dm-transactions'
require 'dm-migrations'

require 'dm-migrations'
require 'dm-mysql-adapter'


socket_file = Pathname.glob(%w[
  /opt/local/var/run/mysql5/mysqld.sock
  tmp/mysqld.sock
  /tmp/mysqld.sock
  tmp/mysql.sock
  /tmp/mysql.sock
  /var/mysql/mysql.sock
  /var/run/mysqld/mysqld.sock
  ]).find { |path| path.socket? }

configuration_options = {
  :adapter => 'mysql2',
  :username => @username,
  :password => @password,
  :database => 'dm_core_test'
}

configuration_options[:socket] = socket_file unless socket_file.nil?

log_dir = DataMapper.root+'log'
log_dir.mkdir unless log_dir.directory?


ActiveRecord::Base.logger = Logger.new(log_dir+'ar.log')
ActiveRecord::Base.logger.level = 0



begin
  printf "\n Connecting to mysql with ActiveRecord ...\n"
  ActiveRecord::Base.establish_connection(configuration_options)
  printf "\n Connect to database #{configuration_options[:database]}\n"
  #ActiveRecord::Base.connection
rescue
  puts "Please check your mysql server or check existence of the database #{configuration_options[:database]}"
  exit
end


configuration_options[:adapter]="mysql"

DataMapper::Logger.new(log_dir+'dm.log', :off)
adapter = DataMapper.setup(:default, configuration_options)

if configuration_options[:adapter]
  sqlfile       = File.absolute_path File.join(File.dirname(File.expand_path(__FILE__)), 'tmp', 'performance.sql')
  mysql_bin     = %w[ mysql mysql5 ].select { |bin| `which #{bin}`.length > 0 }
  mysqldump_bin = %w[ mysqldump mysqldump5 ].select { |bin| `which #{bin}`.length > 0 }
end


class ARExhibit < ActiveRecord::Base #:nodoc:
  set_table_name 'exhibits'

  belongs_to :user, :class_name => 'ARUser', :foreign_key => 'user_id'
end

class ARUser < ActiveRecord::Base #:nodoc:
  set_table_name 'users'

  has_many :exhibits, :foreign_key => 'user_id'
end

class User
  include DataMapper::Resource

  property :id,         Serial
  property :name,       String
  property :email,      String
  property :about,      Text,   :lazy => false
  property :created_on, Date
end

class Exhibit
  include DataMapper::Resource

  property :id,         Serial
  property :name,       String
  property :zoo_id,     Integer
  property :user_id,    Integer
  property :notes,      Text,    :lazy => false
  property :created_on, Date

  belongs_to :user
end

DataMapper.auto_migrate!

def touch_attributes(*exhibits)
  exhibits.flatten.each do |exhibit|
    exhibit.id
    exhibit.name
    exhibit.created_on
  end
end

def touch_relationships(*exhibits)
  exhibits.flatten.each do |exhibit|
    exhibit.id
    exhibit.name
    exhibit.created_on
    exhibit.user
  end
end

c = configuration_options

if sqlfile && File.exists?(sqlfile)

  printf "\nFound data-file. Importing from #{sqlfile}\n"
  #adapter.execute("LOAD DATA LOCAL INFILE '#{sqlfile}' INTO TABLE exhibits")
  `#{mysql_bin.first} -u #{c[:username]} #{"-p#{c[:password]}" unless c[:password].blank?} #{c[:database]} < #{sqlfile}`

else


  printf '\nGenerating data for benchmarking...\n'

  # pre-compute the insert statements and fake data compilation,
  # so the benchmarks below show the actual runtime for the execute
  # method, minus the setup steps

  # Using the same paragraph for all exhibits because it is very slow
  # to generate unique paragraphs for all exhibits.
  notes = Faker::Lorem.paragraphs.join($/)
  today = Date.today

  puts "Inserting #{TIMES} users and exhibits..."
  TIMES.times do
    user = User.create(
      :created_on => today,
      :name       => Faker::Name.name,
      :email      => Faker::Internet.email
    )

    Exhibit.create(
      :created_on => today,
      :name       => Faker::Company.name,
      :user       => user,
      :notes      => notes,
      :zoo_id     => rand(10).ceil
    )
  end

  TIMES = ENV.key?('x') ? ENV['x'].to_i : 10000

  if sqlfile
    answer = nil
    until answer && answer[/\A(?:y(?:es)?|no?)\b/i]
      print("Would you like to dump data into #{sqlfile} (for faster setup)? [Yn]");
      STDOUT.flush
      answer = gets.chomp
    end

    if [ 'y', 'yes' ].include?(answer.downcase)
      FileUtils.mkdir_p(File.dirname(sqlfile))
      #adapter.execute("SELECT * INTO OUTFILE '#{sqlfile}' FROM exhibits;")
      `#{mysqldump_bin.first} -u #{c[:username]} #{"-p#{c[:password]}" unless c[:password].blank?} #{c[:database]} exhibits users > #{sqlfile}`
      puts "File saved\n"
    end
  end
end


puts "Begin Benchmark 1:"
Benchmark.bmbm do |x|
  x.report("Datamapper.get(1):") {
    TIMES.times do
      Exhibit.get(1)
    end
  }
  x.report("ActiveRecord.find(1):") {
    TIMES.times do
      ARExhibit.find(1)
    end
  }
end
puts "End Benchmark 1"
puts "Begin Benchmark 2:"
Benchmark.bmbm do |x|
  x.report("Datamapper.new:") {
    TIMES.times do
      Exhibit.new
    end
  }
  x.report("ActiveRecord.new:") {
    TIMES.times do
      ARExhibit.new
    end
  }
end
puts "End Benchmark 2"
puts "Begin Benchmark 3:"
Benchmark.bmbm do |x|
  attrs = { :name => 'sam', :zoo_id => 1 }
  x.report("Datamapper.new(attr):") {
    TIMES.times do
      Exhibit.new(attrs = { :name => 'sam', :zoo_id => 1 })
    end
  }
  x.report("ActiveRecord.new(attr):") {
    TIMES.times do
      ARExhibit.new(attrs = { :name => 'sam', :zoo_id => 1 })
    end
  }
end
puts "End Benchmark 3"
puts "Begin Benchmark 4:"
Benchmark.bmbm do |x|
  x.report("touch DataMapper.get(1):") {
    TIMES.times do
      touch_attributes(Exhibit.get(1))
    end
  }
  x.report("touch ActiveRecord.find(1):") {
    TIMES.times do
      touch_attributes(ARExhibit.find(1))
    end
  }
end
puts "End Benchmark 4"
puts "Begin Benchmark 5:"
Benchmark.bmbm do |x|
  x.report("Datamapper.all(:limit => 100):") {
    TIMES.times do
      touch_attributes(Exhibit.all(:limit => 100))
    end
  }
  x.report("ActiveRecord.find(:all, :limit => 100):") {
    TIMES.times do
      touch_attributes(ARExhibit.find(:all, :limit => 100))
    end
  }
end
puts "End Benchmark 5"
puts "Begin Benchmark 6:"
Benchmark.bmbm do |x|
  x.report("Datamapper.all(:limit => 100) with relation:") {
    TIMES.times do
      touch_attributes(Exhibit.all(:limit => 100))
    end
  }
  x.report("ActiveRecord.find(:all, :limit => 100) with relation:") {
    TIMES.times do
      touch_attributes(ARExhibit.find(:all, :limit => 100, :include => [ :user ]))
    end
  }
end
puts "End Benchmark 6"

exhibit = {
  :name       => Faker::Company.name,
  :zoo_id     => rand(10).ceil,
  :notes      => Faker::Lorem.paragraphs.join($/),
  :created_on => Date.today
}

puts "Begin Benchmark 7:"
Benchmark.bmbm do |x|
  x.report("Datamapper.create:") {
    TIMES.times do
      Exhibit.create(exhibit)
    end
  }
  x.report("ActiveRecord.create:") {
    TIMES.times do
      ARExhibit.create(exhibit)
    end
  }
end
puts "End Benchmark 7"

puts "Begin Benchmark 8:"
Benchmark.bmbm do |x|
  attrs_first  = { :name => 'sam', :zoo_id => 1 }
  attrs_second = { :name => 'tom', :zoo_id => 1 }
  x.report("Datamapper.new.attributes=:") {
    TIMES.times do
      exhibit = Exhibit.new(attrs_first)
      exhibit.attributes = attrs_second
    end
  }
  x.report("ActiveRecord.new.attributes=:") {
    TIMES.times do
      exhibit = ARExhibit.new(attrs_first)
      exhibit.attributes = attrs_second
    end
  }
end
puts "End Benchmark 8"
puts "Begin Benchmark 9:"
Benchmark.bmbm do |x|
  x.report("Datamapper.update:") {
    TIMES.times do
      Exhibit.get(1).update(:name => 'bob')
    end
  }
  x.report("ActiveRecord.update:") {
    TIMES.times do
      ARExhibit.find(1).update_attributes(:name => 'bob')
    end
  }
end

puts "Begin Benchmark 10:"
Benchmark.bmbm do |x|
  n=TIMES/2.ceil.to_i
  x.report("Datamapper.destroy") {
    n.times do
      Exhibit.first.destroy
    end
  }
  x.report("ActiveRecord.destroy:") {
    n.times do
      ARExhibit.first.destroy
    end
  }
end
puts "End Benchmark 10"
puts "Begin Benchmark 11:"
Benchmark.bmbm do |x|
  x.report("Datamapper.transaction.new") {
    TIMES.times do
      Exhibit.transaction { Exhibit.new }
    end
  }
  x.report("ActiveRecord.transaction.new:") {
    TIMES.times do
      ARExhibit.transaction { ARExhibit.new }
    end
  }
end
puts "End Benchmark 11"

connection = adapter.send(:open_connection)
command = connection.create_command('DROP TABLE exhibits')
command = connection.create_command('DROP TABLE users')
command.execute_non_query rescue nil
connection.close

