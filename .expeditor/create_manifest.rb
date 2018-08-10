#!/usr/bin/env ruby

# By default, this script creates a manifest.json file that contains all the packages in the unstable channel.

require 'date'
require 'net/http'
require 'json'
require 'openssl'

BLDR_API_HOST="willem.habitat.sh"
BLDR_API_USER_AGENT="Chef Expeditor"

# Packages that are present in
# components/automate-deployment/pkg/assets/data/services.json but we wish to
# exclude from the manifest (probably because they are not yet published to the
# depot).
#
# We make this list explicit so that we can make manifest generation fail when
# we fail to get expected package data from the hab depot.
SKIP_PACKAGES = []

def get_latest(channel, origin, name)
  # TODO(ssd) 2018-07-23: Upgrading Habitat currently involves a
  # restart of the entire process tree. Further, the Habitat project
  # releases every 2 weeks, often giving us very little time to
  # validate that the new release works as expected for us.
  #
  # IF YOU UPDATE THESE PINS YOU MUST ALSO UPDATE THE core/hab PIN IN components/automate-deployment/habitat/plan.sh
  #
  pinned_hab_components = {
    "hab"          => { "origin" => "core", "name" => "hab",          "version" => "0.59.0", "release" => "20180712155441"},
    "hab-sup"      => { "origin" => "core", "name" => "hab-sup",      "version" => "0.59.0", "release" => "20180712161546"},
    "hab-launcher" => { "origin" => "core", "name" => "hab-launcher", "version" => "7797",   "release" => "20180625172404"}
  }

  if pinned_hab_components.include?(name)
    return pinned_hab_components[name]
  end

  http = Net::HTTP.new(BLDR_API_HOST, 443)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  req = Net::HTTP::Get.new("/v1/depot/channels/#{origin}/#{channel}/pkgs/#{name}/latest", {'User-Agent' => BLDR_API_USER_AGENT})
  response = http.request(req)
  latest_release = JSON.parse(response.body)
  latest_release["ident"]
end

def get_hab_deps_latest()
  ret = {}
  ["hab", "hab-sup", "hab-launcher"].each do |name|
    d = get_latest("stable", "core", name)
    ret[name] = "#{d["origin"]}/#{d["name"]}/#{d["version"]}/#{d["release"]}"
  end
  ret
end

version = ENV["VERSION"] || DateTime.now.strftime("%Y%m%d%H%M%S")
filename = ENV["VERSION"] || "manifest"

manifest = {}

# The version of the manifest schema - might need to be bumped in the future
manifest["schema_version"] = "1"

# The version of the manifest - the "engineering" version
manifest["build"] = version

# Grab the version of various Habitat components from the deployment-service

hab_deps = get_hab_deps_latest
manifest["hab"] = []
manifest["hab"] << hab_deps["hab"]
manifest["hab"] << hab_deps["hab-sup"]
manifest["hab"] << hab_deps["hab-launcher"]


# Grab the version of hab in the build environment. Comes out in the
# form of 'hab 0.54.0/20180221020527'
hab_version = /(\d+\.\d+\.\d+\/\d{14})/.match(`hab --version`.strip)[0]
manifest["hab_build"] = "core/hab/#{hab_version}"

# Grab the git SHA
manifest["git_sha"] = `git show-ref HEAD --hash`.strip

collections = File.open("components/automate-deployment/pkg/assets/data/services.json") do |f|
  JSON.parse(f.read)
end

pkg_paths_by_collection = {}

non_package_data_keys = %w{ collection binlinks }

collections.each do |collection|
  paths_for_collection = []
  collection.each do |pkg_type, pkg_list|
    next if non_package_data_keys.include?(pkg_type)
    paths_for_collection += pkg_list
  end
  collection_name = collection["collection"]
  pkg_paths_by_collection[collection_name] = paths_for_collection
end

manifest["packages"] = []
pkg_paths_by_collection.each do |name, pkg_paths|

  pkg_paths.each do |pkg_path|
    next if SKIP_PACKAGES.include?(pkg_path)

    package_ident = pkg_path.split("/")
    pkg_origin = package_ident[0]
    pkg_name = package_ident[1]

    latest_release = get_latest("unstable", pkg_origin, pkg_name)

    pkg_version = latest_release["version"]
    pkg_release = latest_release["release"]

    puts "  Adding package #{pkg_origin}/#{pkg_name}/#{pkg_version}/#{pkg_release} from collection #{name}"
    manifest["packages"] << "#{pkg_origin}/#{pkg_name}/#{pkg_version}/#{pkg_release}"
  end
end

manifest["packages"].uniq!
# Sort the packages for easier diff-ing
manifest["packages"].sort!


File.open("#{filename}.json", "w") { |file| file.write(JSON.pretty_generate(manifest)) }
