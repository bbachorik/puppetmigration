#!/bin/ksh

# pupagtinstall.ksh
# version 0.5

# POC: Brent Bachorik

# This script does the following:
#  1.) Installs the new (1.8.3) puppet agent
#  2.) Performs many checks to make sure install is necessary
#  3.) Confirms successful installation
#  4.) Creates a detailed log of activity
#  5.) Moves log file to /var/tmp for capture by remote scp script

# Really, this is a cleanup script for the servers that the puppet automation
# wasn't able to install automatically for whatever reason

# Changelog
# None yet

# Define variables

pupstage=/root/puppet
pupconfigs=/etc/puppetlabs/puppet
pupconf=${pupconfigs}/puppet.conf
pupnodes="radfa0131v11574 radfa0131v11610 radfa4131v11604 radfa0131v301aa"
oldrpmpkgversion=null
newrpmpkgversion=null
pupversionlin=null
oldpkgversion=3.6.2.14-1
newpkgversion=1.8.3-1
scriptname=pupagtinstall.ksh
oldsolpkgname=PUPpuppet
newsolpkgname=puppet-agent
pupversionsol=null
os=null
kernver=$(uname -r)
client=$(hostname)
remotelog=/var/tmp/pupinstall.${client}.log
locallog=/var/tmp/pupinstall.log
set -A statcode NotEvaluated NotEvaluated NotEvaluated NotEvaluated NotEvaluated

# Setup logfile
exec 6> ${locallog} 2>&1

# Define Functions

function setupLog {
        # Setup log file
        printf "[setupLog]\n"
        printf "Starting ${scriptname} script.\n"
        printf "Date:  $(date) \n"
}

function chkOS {
        # Find out current OS
        # Possibilities: Sol 10, Sol 11, RHEL 5, RHEL 6, RHEL 7, Other
        printf "[chkOS]\n"
        case $kernver in
        2.6.18*)
                # This is RHEL / OEL 5
                printf "Confirmed. OS validation - RHEL5!\n"
		statcode[0]=RHEL5
                os=linux
                oldrpmpkgversion=pe-puppet-3.6.2.14-1.pe.el5
                newrpmpkgversion=puppet-agent-1.8.3-1.el5;;
        2.6.32*)
                # This is RHEL / OEL 6
                printf "Confirmed. OS validation - RHEL6!\n"
		statcode[0]=RHEL6
                os=linux
                oldrpmpkgversion=pe-puppet-3.6.2.14-1.pe.el6
                newrpmpkgversion=puppet-agent-1.8.3-1.el6;;
        3.10*)
                # This is RHEL / OEL 7
                printf "Confirmed. OS validation - RHEL7!\n"
		statcode[0]=RHEL7
                os=linux
                oldrpmpkgversion=pe-puppet-3.6.2.14-1.pe.el7
                newrpmpkgversion=puppet-agent-1.8.3-1.el7;;
        5.10*)
                # This is Solaris 10
                printf "Confirmed. OS validation - Solaris 10.\n"
		statcode[0]=Sol10
                os=solaris;;
        5.11*)
                # This is Solaris 11
                printf "Confirmed. OS validation - Solaris 11.\n"
		statcode[0]=Sol11
                os=solaris;;
        *)
                # Unknown OS
                printf "Unknown OS.\n"
		statcode[0]=ERR-Unknown
		scriptFin;;
        esac
}

function agtStatus {
        # First, find out if this server is the puppet master, console or database svr
        printf "[agtStatus]\n"
        for node in $pupnodes
        do
                if [[ "${client}" = "$node" ]];then
                        printf "This is a puppet server node!\n"
                        printf "Do not do anything further. Exit.\n"
			statcode[1]=ERR-${node}
			scriptFin
		else
			printf "This server, ${client}, is not puppet server ${node}.\n"
			statcode[1]=No
                fi
        done

        # Find out if agent is installed and version
        if [[ "$os" = "linux" ]];then
                # This is a RedHat/OEL server
                printf "Linux...\n"
		agtStatusLinux

        else
                # This is a Solaris server
                printf "Solaris...\n"
		agtStatusSolaris
        fi
}

function agtStatusLinux {
        # This is a linux server
        printf "[agtStatusLinux]\n"

	pupversionlin=$(rpm -qa |egrep "${oldrpmpkgversion}|${newrpmpkgversion}")

	case $pupversionlin in
        puppet-agent-1.8.3-1*)
        	# New agent installed
		printf "Agent installed. New version.\n"
		statcode[2]=New
		scriptFin;;
        pe-puppet-3.6.2.14-1*)
                # Legacy agent installed
                printf "Agent installed. Legacy version.\n"
		statcode[2]=WARNING-Legacy
		scriptFin;;
        "")
        	# No agent installed
                printf "No agent seems to be installed!\n"
		statcode[2]=NotInstalled
		agtInstall;;
        *)
        	# Unknown agent version installed
                printf "Agent installed. Unknown version! Abort.\n"
		statcode[2]=ERR-Unknown
		scriptFin;;
        esac
}

function agtStatusSolaris {
        # This is a solaris server
        printf "[agtStatusSolaris]\n"

	currentpkgname=$(pkginfo | egrep "${oldsolpkgname}|${newsolpkgname}" | grep -v release)
        pupversionsol=$(pkginfo -l ${currentpkgname} | grep VERSION | awk '{print $2}')

        case $pupversionsol in
        ${newpkgversion}*)
        	# New agent installed
                printf "Agent installed. New version.\n"
		statcode[2]=New
		scriptFin;;
        ${oldpkgversion}*)
                # Legacy agent installed
                printf "Agent installed. Legacy version.\n"
		statcode[2]=WARNING-Legacy
		scriptFin;;
        "")
                # No agent installed
                # We need to skip some steps: backups, uninstall, purge
                printf "No agent seems to be installed!\n"
		statcode[2]=NotInstalled
		agtInstall;;
        *)
                # Unknown agent version installed
                printf "Agent installed. Unknown version! Abort.\n"
		statcode[2]=ERR-Unknown
		scriptFin;;
        esac
}

function agtInstall {
	# Install new agent
        printf "[agtInstall]\n"

	# Agent isn't installed; proceed
	if [[ "$os" = "linux" ]];then
		printf "Linux ...\n"
		agtInstallLinux
	else
		printf "Solaris ...\n"
		agtInstallSolaris
	fi
}

function agtInstallLinux {
        # Install new linux agent
        # Point to new puppet master
        printf "[agtInstallLinux]\n"

	printf "No agent installed. Taking care of that now...\n"
	cd $pupstage
	curl -k https://radfa0131v301aa.altess.army.mil:8140/packages/current/install.bash | sudo bash
	installConfirm
}

function agtInstallSolaris {
        # Install new solaris agent
        # Point to new puppet master
        printf "[agtInstallSolaris]\n"

	printf "No agent installed. Taking care of that now...\n"
	cd $pupstage
	/usr/sfw/bin/wget --no-check-certificate https://${wgettarget}
	chmod +x install.bash
	PATH=$PATH:/usr/sfw/bin;export PATH
	$pupstage/install.bash
	installConfirm
}

function installConfirm {
        # Confirm installation is successful
        printf "[installConfirm]\n"

        # Check for valid puppet.conf file
        if [[ -f $pupconf && "$(grep server $pupconf | awk '{print $3}')" = "radfa0131v301aa.altess.army.mil" ]];then
                printf "puppet.conf looks good.\n"
		statcode[3]=Valid
	else
		printf "Review puppet.conf for correct puppet master!.\n"
		statcode[3]=ERR-Invalid
        fi

        # Check for services
        # For now, only report on puppet agent service; mcollective will start after 2nd puppet run
	pgrep puppet
	if (( $? == 0 ));then
		printf "puppet agent running.\n"
		statcode[4]=Running
	else
		printf "puppet agent NOT running.\n"
		statcode[4]=ERR-NotRunning
	fi
	scriptFin
}

function scriptFin {
        # Shutdown log file gracefully
        printf "[scriptFin]\n"
	print ${statcode[*]} | egrep "ERR|WARNING"
	if (( $? == 0 ));then
		# There were errors or warnings 
		printf "Install script ${scriptname} encountered errors or warnings!\n"
		printf "ERROR / WARNING STATUS -----------------\n"
		printf "Client OS               : ${statcode[0]}\n"
		printf "Puppet Server           : ${statcode[1]}\n"
		printf "Puppet Agent Installed  : ${statcode[2]}\n"
		printf "Puppet conf file        : ${statcode[3]}\n"
		printf "Puppet agent service    : ${statcode[4]}\n"
		printf "-----------------------------------------\n"
	        printf "${scriptname} script complete.\n"
		printf "Date:  $(date) \n"
	else	
		# Script ran without error or warning
        	printf "Puppet agent has been Successfully upgraded!\n"
                printf "OK STATUS ------------------------------\n"
                printf "Client OS               : ${statcode[0]}\n"
                printf "Puppet Server           : ${statcode[1]}\n"
                printf "Puppet Agent Installed  : ${statcode[2]}\n"
                printf "Puppet conf file        : ${statcode[3]}\n"
                printf "Puppet agent service    : ${statcode[4]}\n"
                printf "----------------------------------------\n"
	        printf "${scriptname} script complete.\n"
		printf "Date:  $(date) \n"
	fi
}

function stgLog {
	# Copy log file to /var/tmp so remote scp script can capture it
        printf "[stgLog]\n"

	# Close log redirection
	echo "Closing log redirection..."
	exec 6>&-
        printf "Script output to logfile stopped." >> ${locallog}
	cp ${locallog} ${remotelog}
	chmod 440 ${remotelog}
	chown altesssa:syseng ${remotelog}
}

# Main section
setupLog
chkOS 
agtStatus
stgLog

exit 0
