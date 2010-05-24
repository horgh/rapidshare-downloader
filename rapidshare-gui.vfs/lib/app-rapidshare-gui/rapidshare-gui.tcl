package provide app-rapidshare-gui 1.0

#!/usr/bin/env wish
#
# 0.1 - Apr 3 2010
#
# TODO:
#  - Load urls from a text file
#  - Fix bug where closing via "X" leaves hang if we are sleeping/countdown
#

package require rs
package require Tk

namespace eval rs_gui {
	# minutes to wait between fetches / attempts
	set wait 16
	set wait_err 5

	set version 0.1

	set directory []

	# progress bar variable
	set progress 0

	# used for waiting on gui
	set wait_tk 0

	# flag for whether download running
	set running 0

	# tied to status label
	set status_label []

	# tied to stats label
	set stats_label "0.0 MiB downloaded"
}

proc log_update {text} {
	.log configure -state normal
	.log insert end "$text\n"
	.log configure -state disabled
	.log see end
}

# called from file -> set path
proc set_path {} {
	set dir [tk_chooseDirectory]
	if {$dir != ""} {
		set rs_gui::directory $dir
	}
	save_config
}

# called from file -> exit menu
proc file_exit {} {
	exit
}

# called from file -> select theme
proc change_theme {theme} {
	ttk::style theme use $theme
}

proc about {} {
	tk_messageBox -message "RapidShare Downloader v${rs_gui::version}.\nhttp://www.summercat.com"
}

proc add_button {} {
	set url [.newurl get]
	if {$url != ""} {
		if {[catch {rs::validate_url $url} output]} {
			tk_messageBox -message "Invalid URL. Please use form http://rapidshare.com/..."
			return
		}
		.downloads insert .dl_parent end -text $url
		.newurl delete 0 end
	}
}

proc delete_button {} {
	set tree_selected [.downloads selection]
	if {$tree_selected != ""} {
		.downloads delete $tree_selected
	}
}

proc stop_button {} {
	foreach after_id [after info] {
		after cancel $after_id
	}
	set rs_gui::running 0
	.start configure -state normal
	reset_gui
	log_update "Reset!"
}

# update stats label with how much downloaded
proc update_stats {} {
	set mb_down [scan $rs_gui::stats_label %f]
	set mb_down [expr $mb_down + [rs::byte_to_megabyte $rs::download_size]]
	set rs_gui::stats_label "[format %.2f $mb_down] MiB downloaded"
}

proc start_button {} {
	if {$rs_gui::running == 1} {
		return
	}
	set rs_gui::running 1
	.start configure -state disabled

	while {[llength [.downloads children .dl_parent]] > 0} {
		set curr_item [lindex [.downloads children .dl_parent] 0]
		set url [.downloads item $curr_item -text]

		set file_name [rs::get_filename $url]

		set rs_gui::progress 0

		if {[catch {process_url $url $file_name} output]} {
			log_update $output
			# We got an error, so countdown error time
			set wait [expr {int($rs_gui::wait_err + rand() * 5)*60}]
			log_update "Waiting for $wait seconds due to failure"
		} else {
			if {$rs_gui::running == 0} {
				return
			}
			# Delete first item in download list
			.downloads delete [lindex [.downloads children .dl_parent] 0]
			# Add file to completed
			.downloads insert .complete_parent end -text $file_name
			update_stats

			log_update "Successfully downloaded $file_name!"
			# Success. Wait success time
			set wait [expr {int($rs_gui::wait + rand() * 5)*60}]
			log_update "Waiting for $wait seconds due to success"
		}

		reset_gui
		countdown $wait
		wait_for $wait
	}

	set rs_gui::running 0
	.start configure -state normal
}

proc http_progress {token size downloaded} {
	set rate [format %.2f [rs::calc_rate_avg $downloaded $rs::rate_time]]
	set percent [expr 100 * $downloaded / $size]
	set mb_status "[rs::byte_to_megabyte $downloaded] / [rs::byte_to_megabyte $size]"
	set timeleft [rs::time_left $size $downloaded $rate]

	if {$rs_gui::running == 0} {
		http::reset $token
		return
	}

	set rs_gui::status_label "[format "%+13s MB %+5s%% %+10s KB/s %+10s remaining" $mb_status $percent $rate $timeleft]"
	set rs_gui::progress [expr int($percent)]
}

proc wait_for {seconds} {
	after [expr $seconds * 1000] {set rs_gui::wait_tk 1}
	tkwait variable rs_gui::wait_tk
}

proc countdown {seconds} {
		if {$seconds <= 0} {
			return
		}

		set rs_gui::status_label "Waiting for [rs::clockify $seconds]"

		incr seconds -1
		after 1000 [list countdown $seconds]
}

proc process_url {url file_name} {
	if {[catch {rs::get_inner_url $url} inner_url]} {
		error "Error fetching inner url. Bad rapidshare URL?"
	}
	log_update "Found url $inner_url"

	# Wait
	set pause [expr {int((15 + rand() * 20))}]
	log_update "Waiting for $pause seconds..."
	countdown $pause
	wait_for $pause

	if {[catch {rs::get_data_url $inner_url} data_result]} {
		error "Error fetching data url: $data_result"
	}
	set data_url [lindex $data_result 0]
	set sleep [expr [lindex $data_result 1] + 10]
	log_update "Found url $data_url"

	# Wait
	log_update "Waiting for $sleep seconds before fetch..."
	countdown $sleep
	wait_for $sleep

	if {[catch {rs::fetch_data $data_url ${rs_gui::directory}/${file_name}} fetch_result]} {
		error "Error fetching data: $fetch_result"
	}
}

# Put all status back to original state
proc reset_gui {} {
	set rs_gui::status_label []
	set rs_gui::progress 0
}

# Directory setup
proc init_config {} {
	set config [file join $starkit::topdir config]
	if {![file exists $config]} {
		set directory [pwd]
	} else {
		set fid [open $config r]
		set config_data [split [read -nonewline $fid]]
		close $fid
		set directory [lindex $config_data 0]
	}

	set rs_gui::directory $directory
}

# Safe config
proc save_config {} {
	set config [file join $starkit::topdir config]
	set fid [open $config w]
	puts -nonewline $fid $rs_gui::directory
	close $fid
}

init_config

wm title . "RapidShare downloader"
#ttk::style theme use plastik
# Used to fix background on plastik theme
#. configure -background "#efefef"

# menu bar
menu .menu -borderwidth 1 -tearoff 0
. configure -menu .menu

menu .menu.file -tearoff 0
.menu add cascade -label "File" -menu .menu.file -underline 0

# theme
menu .menu.theme -tearoff 0
.menu.file add cascade -label "Select theme" -menu .menu.theme
foreach theme [ttk::style theme names] { 
	.menu.theme add command -command "change_theme $theme" -label $theme
}

# exit
.menu.file add separator
.menu.file add command -command "file_exit" -label "Exit"

# set path
.menu add command -command "set_path" -label "Set download path" -underline 0

# help2 as tk right aligns name help?
menu .menu.help2 -tearoff 0
.menu add cascade -label "Help" -menu .menu.help2 -underline 0
.menu.help2 add command -command "about" -label "About"


# status area
ttk::frame .status_frame
ttk::label .status_text -width 70 -text "" -textvariable rs_gui::status_label -anchor center
ttk::progressbar .progress -orient horizontal -length 500 -variable rs_gui::progress

grid .progress -in .status_frame -row 1 -column 1
grid .status_text -in .status_frame -row 2 -column 1


# url entry + add / del buttons
ttk::frame .url_frame
ttk::button .add -text "Add" -command "add_button"
ttk::button .delete -text "Delete selected" -command "delete_button"
ttk::entry .newurl -width 45

grid .newurl -in .url_frame -row 1 -column 1
grid .add -in .url_frame -row 1 -column 2
grid .delete -in .url_frame -row 1 -column 3


# log + scrollbars + start
ttk::frame .log_frame
text .log -width 70 -height 10 -yscrollcommand ".log_y set" -state disabled
ttk::scrollbar .log_y -command ".log yview" -orient v

grid .log -in .log_frame -row 1 -column 1 -sticky nsew
grid .log_y -in .log_frame -row 1 -column 2 -sticky ns


# control buttons
ttk::frame .control_frame
ttk::button .start -text "Start" -command "start_button"
ttk::button .stop -text "Stop/Reset" -command "stop_button"

grid .start -in .control_frame -row 1 -column 1
grid .stop -in .control_frame -row 1 -column 2


# url list
ttk::frame .downloads_frame
ttk::treeview .downloads -selectmode browse -show tree -yscrollcommand ".urls_y set"
.downloads column #0 -width 700
.downloads insert {} 0 -id .dl_parent -text "To Download" -open true
.downloads insert {} 1 -id .complete_parent -text "Completed" -open true
ttk::scrollbar .urls_y -command ".downloads yview" -orient v

grid .downloads -in .downloads_frame -row 1 -column 1
grid .urls_y -in .downloads_frame -row 1 -column 2 -sticky ns


# download stats
ttk::frame .stats -relief sunken -padding 1
ttk::label .stats_text -textvariable rs_gui::stats_label -anchor e

grid .stats_text -in .stats -row 1 -column 1


grid .downloads_frame -in . -row 1 -column 1 -sticky nsew
grid .url_frame -in . -row 2 -column 1
grid .log_frame -in . -row 3 -column 1
grid .status_frame -in . -row 4 -column 1
grid .control_frame -in . -row 5 -column 1 -ipady 5
grid .stats -in . -row 6 -column 1 -sticky nsew
