require 'csv'
require 'fileutils'
require 'optparse'
require 'digest'


$inputTSV = ''
$inputDIR = ''
$desinationDIR = ''

ARGV.options do |opts|
  opts.on("-t", "--target=val", String)  { |val| $inputDIR = val }
  opts.on("-o", "--output=val", String)     { |val| $desinationDIR = val }
  opts.parse!
end

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end
end
# Set package variables

$packagename = File.basename($inputDIR)
$packagedir =  "#{$desinationDIR}/#{$packagename}"
$objectdir = "#{$desinationDIR}/#{$packagename}/objects"
$accessdir = "#{$desinationDIR}/#{$packagename}/objects/access"
$metadatadir = "#{$desinationDIR}/#{$packagename}/metadata"
$logdir = "#{$desinationDIR}/#{$packagename}/logs"
$existinghashpass = '0'
EventLogs = Array.new

# Start setting up log output
@premis_structure = Hash.new
@premis_structure['package name'] = $packagename
@premis_structure['package source'] = $inputDIR
@premis_structure['creation time'] = Time.now
@premis_structure['events'] = []

def premisreport(action,outcome)
    @premis_structure['events'] << [{'eventname':action,'eventoutcome':outcome}] 
end
  

#Exit if target not directory

if ! File.directory?($inputDIR) || ! File.directory?($desinationDIR)
  puts "Please confirm inputs are valid directories. Exiting.".red
  exit
end

# Create package structure
if ! File.exists?($packagedir)
  puts "Creating package at #{$packagedir}".green
  Dir.mkdir $packagedir
else
  puts "Directory with package name already exists in ouput directory! Exiting.".red
  exit
end
if ! File.exists?($objectdir)
  Dir.mkdir $objectdir
end
if ! File.exists?($metadatadir)
  Dir.mkdir $metadatadir
end
if ! File.exists?($logdir)
  Dir.mkdir $logdir
end

# Copy Target directory structure
if system('rsync','-av',"#{$inputDIR}/",$objectdir)
  puts "Files transferred to target successfully".green
  premisreport('migratefiles','pass')
else
  puts "Transfer error: Exiting"
  exit
end

## OPTIONAL
## Move certain files to access directory
Dir.mkdir($accessdir)
access_files = Dir.glob("#{$objectdir}/*.pdf")
access_files.each do |file|
  FileUtils.cp(file,$accessdir)
  FileUtils.rm(file)
end

#check for existing metadata and validate
if File.exist?("#{$objectdir}/metadata")
  FileUtils.cp_r("#{$objectdir}/metadata/.",$metadatadir)
  FileUtils.rm_rf("#{$objectdir}/metadata")
  puts "Existing Metadata detected, moving to metadata directory".green
  priorhashmanifest = Dir.glob("#{$metadatadir}/*.md5")[0]
  if File.exist? priorhashmanifest
    puts "Attempting to validate using existing hash information for Package:#{$packagename}".green
    hashvalidation = `hashdeep -k #{priorhashmanifest} -xrl #{$objectdir}`
    if hashvalidation.empty?
      puts "WOO! Existing hash manifest validated correctly".green
      premisreport('fixitycheck','pass')
      $existinghashpass = '1'
    else
      puts "Existing hash manifest did not validate. Will generate new manifest/check transfer integrity".red
      FileUtils.rm(priorhashmanifest)
      $existinghashpass = '2'
    end
  end
end

if  $existinghashpass != '1'
  puts "Verifying transfer integrity for package: #{$packagename}".green
  target_Hashes = Array.new
  $target_list = Dir.glob("#{$inputDIR}/**/*")
  $target_list.each do |target|
    if ! File.directory?(target) && ! File.dirname(target).include?('metadata')
      target_hash = Digest::MD5.file(target).to_s
      target_Hashes << target_hash
    end
  end

  transferred_Hashes = Array.new
  $transferred_list = Dir.glob("#{$objectdir}/**/*")
  $transferred_list.each do |transfer|
    if ! File.directory?(transfer)
      transfer_hash = Digest::MD5.file(transfer).to_s
      transferred_Hashes << transfer_hash
    end
  end
  #compare generated hashes to verify transfer integrity
  hashcomparison = transferred_Hashes - target_Hashes | target_Hashes - transferred_Hashes
  if hashcomparison.empty?
    premisreport('fixitycheck','pass')
    puts "Files copied successfully".green
    puts "Generating new checksums.".green
    hashmanifest = "#{$metadatadir}/#{$packagename}.md5"
    command = 'hashdeep -rl -c md5 ' + $objectdir + ' >> ' +  hashmanifest
    if system(command)
        premisreport('fixitygeneration','pass')
    end
  else
    puts "Mismatching hashes detected between target directory and transfer directory. Exiting.".red
    exit
  end
end

# Check if exiftool metadata exists and generate if needed
technicalmanifest = "#{$metadatadir}/#{$packagename}.json"
command = 'exiftool -json -r ' + $objectdir + ' >> ' +  technicalmanifest
if Dir.glob("#{$metadatadir}/*.json")[0].nil?
  puts "Generating technical metadata".green
  system(command)
else
  priorhashmanifest = Dir.glob("#{$metadatadir}/*.json")[0]
  if File.exist?(priorhashmanifest)
    if $existinghashpass == '2'
      puts "As original hash manifest was inaccurate, generating new technical metadata".green
      FileUtils.rm(technicalmanifest)
      system(command)
    end
  end
end

#Bag Package
puts "Creating bag from package".green
if system('bagit','baginplace',"#{$desinationDIR}/#{$packagename}")
  puts "Bag created successfully".green
else
  puts "Bag creation failed".red
  exit
end

#TAR Bag
puts "Creating TAR from Bag".green
Dir.chdir($desinationDIR)
if system('tar','-cvf',"#{$packagedir}.tar",$packagename)
  puts "TAR Created successfully: Cleaning up".green
  FileUtils.rm_rf($packagename)
  system('cowsay',"Package creation finished for:#{$packagename}")
else
  puts "TAR creation failed. Exiting.".red
  exit
end

puts @premis_structure

