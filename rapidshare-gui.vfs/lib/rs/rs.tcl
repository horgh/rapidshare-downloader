#!/usr/bin/env tclsh8.5
#
# 0.2 - Apr 3 2010
#  - Separated into a library for GUI and CLI versions
#
# 0.1 - Mar 15 2010
#
# TODO:
#  - select new filename if filename exists
#  - more intelligent wait between fetches rather than one size for all
#

package require http
package provide rs 0.2

namespace eval rs {
	http::config -useragent "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.6) Gecko/20091216 Firefox/3.0.6"

	set query [http::formatQuery dl.start Free submit "Free user"]
	set method POST

	# outer page (first page) regexp
	set inner_regexp {<form id="ff" action="(.*?)"}
	set data_regexp {<form name="dlf" action="(.*?)"}
	set sleep_regexp {var c=(.*?);}

	set urls []
	set success []

	# used for rate calculation
	set rate_time []

	# size downloaded. updated to last size of completed file
	set download_size []
}


# attempt to validate we have correct url
proc rs::validate_url {url} {
	if {![regexp -- {^(?:http://)??rapidshare.com} $url]} {
		error "Invalid URL"
	}
}

# get file name from a url
proc rs::get_filename {url} {
	return [string range $url [expr [string last / $url]+1] end]
}

# convert bytes to MB
proc rs::byte_to_megabyte {bytes} {
	return [format %.2f [expr 1.0 * $bytes / 1048576]]
}

# calculate rate (average)
proc rs::calc_rate_avg {bytes start_time} {
	set duration [expr [clock seconds]-$start_time]
	set kb_rate [expr 1.0 * $bytes / 1024 / $duration]

	return $kb_rate
}

# Format a time given in seconds nicely: 00:00:00
proc rs::clockify {seconds} {
	return [format "%02d:%02d:%02d" [expr $seconds / 3600] [expr ($seconds % 3600) / 60] [expr $seconds % 60]]
}

# calculate time left
# rate is in KB
proc rs::time_left {size downloaded rate} {
	# bytes
	set data_left [expr $size - $downloaded]
	# seconds
	set time_left [expr {int($data_left / ($rate * 1024.0))}]

	return [rs::clockify $time_left]
}

# Fetch data from url. Store in a file
proc rs::fetch_data {url file_name} {
	set fid [open $file_name w]

	set rs::rate_time [clock seconds]
	set token [http::geturl $url -query $rs::query -method $rs::method -channel $fid -progress http_progress -blocksize 104858]
	
	close $fid

	if {[http::error $token] ne ""} {
		error "Error downloading $file_name!"
	}

	set rs::download_size [http::size $token]

	http::cleanup $token
}

# fetch url html
proc rs::fetch_url {url} {
	set token [http::geturl $url -query $rs::query -method $rs::method]
	set data [http::data $token]
	http::cleanup $token

	# Debug html output
	#set fid [open "debug.txt" a]
	#puts $fid "*** NEW"
	#puts $fid $data
	#close $fid
	
	return $data
}

# find inner url to second html page
proc rs::get_inner_url {url} {
	set data [rs::fetch_url $url]
	if {![regexp -- $rs::inner_regexp $data -> inner_url]} {
		error $data
	}
	#puts "Found url $inner_url"
	return $inner_url
}

# Examine html (data page html) for specific error
proc rs::find_error {data} {
	if {[regexp -- {Unfortunately right now our servers are overloaded} $data]} {
		return "Rapidshare servers overloaded"
	} elseif {[regexp -- {You have reached the download limit} $data]} {
		return "Download limit reached. Please wait"
	} elseif {[regexp -- {Currently a lot of users are downloading} $data]} {
		return "Rapidshare has too many users downloading files"
	} else {
		return "Unknown error. Has rapidshare layout changed?"
	}
}

# find data url & the time to wait
proc rs::get_data_url {url} {
	set data [rs::fetch_url $url]
	if {![regexp -- $rs::data_regexp $data -> inner_url]} {
		error [rs::find_error $data]
	}
	if {![regexp -- $rs::sleep_regexp $data -> sleep_time]} {
		error [rs::find_error $data]
	}
	#puts "Found url $inner_url"
	return [list $inner_url $sleep_time]
}
