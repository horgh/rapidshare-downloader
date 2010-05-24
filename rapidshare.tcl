#!/usr/bin/env tclsh8.5
#
# 0.2 - Apr 3 2010
#  - Separated into GUI and CLI versions
#
# 0.1 - Mar 15 2010
#
# Usage: ./rapidshare.tcl <list of urls.txt>
#
# Usage notes:
#  - Overwrites target download file silently if it exists.
#  - Do not edit urllist.txt while in use. It is overwritten as files complete
#  - <list of urls.txt> expects urls to first page of download from rapidshare, i.e. the page which there is button to click "free user", separated by newlines
#

source rs.tcl

namespace eval rs_cli {
	# minutes to wait between fetches / attempts (will be random slightly more)
	set wait 16
	set wait_err 5

	set urls []
	set success []
}


# wait for given amount of seconds & update prompt every second for countdown
proc wait_for {seconds} {
	while {$seconds > 0} {
		puts -nonewline "\r[rs::clockify $seconds]"
		flush stdout

		# wait for 3 seconds, or $seconds if < 10 left
		incr seconds -3
		if {$seconds >= 3} {
			after 3000
		} else {
			after [expr $seconds * 1000]
		}
	}

	puts []
}

# Print status of download every blocksize bits
proc http_progress {token size downloaded} {
	set rate [format %.2f [rs::calc_rate_avg $downloaded $rs::rate_time]]
	set percent [expr 100 * $downloaded / $size]
	set mb_status "[rs::byte_to_megabyte $downloaded] / [rs::byte_to_megabyte $size]"
	set timeleft [rs::time_left $size $downloaded $rate]

	puts -nonewline "\r[format "%+23s MB %+5s%% %+10s KB/s %+10s" $mb_status $percent $rate $timeleft]"
	flush stdout
}

# Take initial url and download the file
proc process_url {url file_name} {
	puts "Getting inner url..."
	# get inner url from outer url
	if {[catch {rs::get_inner_url $url} inner_url]} {
		error "Error fetching inner url."
	}
	puts "Found url $inner_url"

	set pause [expr {int((15 + rand() * 20))}]
	puts "Waiting $pause seconds..."
	wait_for $pause

	puts "Getting data url..."
	# get data url from inner url
	if {[catch {rs::get_data_url $inner_url} data_result]} {
		error "Error fetching data url: $data_result"
	}
	set data_url [lindex $data_result 0]
	puts "Found url $data_url"

	set sleep [expr [lindex $data_result 1] + 10]
	puts "Waiting $sleep seconds before fetch..."
	wait_for $sleep

	puts "Fetching $file_name..."
	if {[catch {rs::fetch_data $data_url $file_name} fetch_result]} {
		error "Error fetching data: $fetch_result"
	}
}

# load urls from file
proc load_urls {file_name} {
	set fid [open $file_name r]
	set data [read -nonewline $fid]
	close $fid
	foreach url $data {
		lappend rs_cli::urls $url
	}
}

# write urls to file
proc write_urls {file_name} {
	puts "Updating $file_name with current list..."
	set fid [open $file_name w]
	foreach url $rs_cli::urls {
		puts $fid $url
	}
	close $fid
}


# Begin
if {$argc != 1} {
	puts "Usage: ./rapidshare.tcl <list of urls.txt>"
	return -1
}

set url_file [lindex $argv 0]
load_urls $url_file
puts "Loaded [llength $rs_cli::urls] urls.\n"

while {[llength $rs_cli::urls] > 0} {
	puts "[llength $rs_cli::urls] files left to download."
	set url [lindex $rs_cli::urls 0]
	set file_name [rs::get_filename $url]

	puts "Beginning fetch of $file_name."

	if {[catch {process_url $url $file_name} result]} {
		puts "Error: $result"
		# Lower wait period if we have an error as hopefully means rs blocked us
		set wait [expr {int($rs::wait_err + rand() * 5)}]
	} else {
		# Remove url from list since success dl
		set rs_cli::urls [lrange $rs_cli::urls 1 end]
		puts "\nRemoving url from list due to success."
		write_urls $url_file

		lappend rs_cli::success $url

		# We're done
		if {[llength $rs_cli::urls] == 0} {
			break
		}

		# Set wait to time between fetches
		set wait [expr {int($rs::wait + rand() * 5)}]
	}

	puts "Waiting for $wait min before next attempt / file."
	wait_for [expr $wait * 60]
}

puts "No urls left.\n"

foreach s $rs_cli::success {
	puts "Successfully completed $s."
}
