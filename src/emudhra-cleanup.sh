#! /bin/sh
#
# Originally written by Jan Schaumann
# <jschauma@netmeister.org> in October 2026.
#
# This script will attempt to remove CA bundles
# affected by the eMudhra root CA compromise from
# well-known CA bundles.
#
# See the manual page for details.
#
# 100% human generated.
set -eu

set -o noclobber
umask 077

PATH=/bin:/usr/bin:/sbin:/usr/bin
export PATH

TDIR=""

BACKUP="no"
BUNDLE_FILES=""
DEFAULT_BUNDLE="/etc/ssl/cert.pem"
DETECT_ONLY="no"
SEARCH_PATHS=""
LOGGING="no"
OS="$(uname)"
PROGNAME="${0##*/}"
PYTHON_PIP=""
VERBOSITY=0
VERSION="0.8"

KNOWN_BUNDLES="
${DEFAULT_BUNDLE}
/etc/ssl/ca-bundle.pem
/etc/pki/tls/certs/ca-bundle.crt
/etc/ssl/certs/ca-certificates.crt
"

CA_CERTS_CONF="/etc/ca-certificates.conf"

HOMEBREW="/opt/homebrew"

ROOTS="
D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4|AAA Certificate Services
86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B|emSign ECC Root CA - G3
F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5|emSign Root CS CA - G3
7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D|emSign Root TLS CA - G3
"

###
### Functions
###

backup() {
	local f="${1}"

	if [ ! -f "${f}" ]; then
		return
	fi

	if [ x"${BACKUP}" = x"yes" ]; then
		verbose "Backing up ${f}..."
		cp -p ${f} ${f}.pre-emudhra-cleanup	
	fi
}

cleanup() {
	rm -fr "${TDIR}"
}

error() {
	local readonly msg="${1}"

	warn "${msg}" "ERROR"
	exit 1
	# NOTREACHED
}

findBundles() {
	local cmd

	verbose "Finding possible CA bundles..."

	>"${TDIR}/bundles"

	oIFS=""
	IFS="
"
	for p in ${SEARCH_PATHS}; do
		# GNU needs "find <path> -xdev";
		# BSD needs "find -x <path>"
		cmd="find -x '${p}'"
		if [ x"${OS}" = x"Linux" ]; then
			cmd="find '${p}' -xdev"
		fi
		cmd="${cmd} -name '*.pem' -o -name '*.crt' -print 2>/dev/null"

		verbose "Running \"${cmd}\"..." 2
		set +e
		eval ${cmd} >> "${TDIR}/bundles"
		set -e
	done
	IFS="${oIFS}"

	num=$(wc -l <"${TDIR}/bundles")

	if [ ${num} -eq 0 ]; then
		verbose "No bundles found."
		exit 0
		# NOTREACHED
	fi
}

fixPip() {
	verbose "Fixing pip..."
	local cfg pipdir pipexec py
	local err

	local bundle="${PIP_CERT:-${DEFAULT_BUNDLE}}"

	if [ ! -f "${bundle}" ]; then
		err="${bundle} does not exist."
		if [ -z "${PIP_CERT:-}" ]; then
			err="${err}
Specify an alternative bundle by setting the PIP_CERT environment variable."
		else
			err="${err}
Check the value of the PIP_ENV environment variable."
		fi
		error "${err}"
		# NOTREACHED
	fi

	if ! expr "${PYTHON_PIP}" : "\/" >/dev/null 2>&1; then
		error "Argument to '-p' must be an absolute path."
		# NOTREACHED
	fi


	# There's some guess-work here:  if you
	# specify a "pip", say "pip3.10", then we will
	# invoke what we hope is the corresponding
	# "python3.10".
	pipexec="${PYTHON_PIP##*/}"
	pipdir="${PYTHON_PIP%/*}"
	py="${PYTHON_PIP}"

	if expr "${pipexec}" : "pip" >/dev/null 2>&1; then
		py="${pipdir}/python$(echo ${pipexec} | sed -e 's/pip//')"
	elif ! expr "${pipexec}" : "python" >/dev/null 2>&1; then
		error "Specify either a python or pip executable path."
		# NOTREACHED
	fi

	if [ ! -x "${py}" ]; then
		error "'${py}' not executable."
		# NOTREACHED
	fi


	cfg="$(${py} -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')/sitecustomize.py"

	if grep -q "^import os; os.environ.setdefault(\"PIP_CERT\", \"${bundle}" "${cfg}"; then
		verbose "'${cfg}' already fixed."
		return
	fi
	backup "${cfg}"

	printf "import os; os.environ.setdefault(\"PIP_CERT\", \"${bundle}\")\n" >> "${cfg}"
	chmod 644 "${cfg}"

	verbose "${cfg} updated."
}

handleBundles() {
	if [ -z "${BUNDLE_FILES}" -a -n "${SEARCH_PATHS}" ]; then
		findBundles
	fi
	updateBundles
	if [ -z "${BUNDLE_FILES}" -a -z "${SEARCH_PATHS}" ]; then
		updateConf
	fi
}

log() {
	local msg

	if [ x"${LOGGING}" != x"yes" ]; then
		return
	fi

	if [ -f "${LOGFILE}" ]; then
		msg="$(date '+%Y-%m-%d %H:%M:%S %z') [$$] ${1}"
		printf -- "${msg}\n" >> "${LOGFILE}"
	fi
	logger -t emudhra-cleanup -- "${1}"
}

updateBundles() {
	local bundles="${BUNDLE_FILES}"

	verbose "Inspecting bundles..."

	if [ -z "${bundles}" ]; then
		bundles="${KNOWN_BUNDLES}"
		if [ -d "${HOMEBREW}" ]; then
			bundles="${bundles}
${HOMEBREW}/etc/*/cert.pem"
		fi
	fi

	oIFS=""
	IFS="
"
	if [ -n "${SEARCH_PATHS}" ]; then
		bundles="${BUNDLE_FILES}
$(cat "${TDIR}/bundles")"
	fi

	for b in ${bundles}; do
		updateOneBundle "${b}"
	done
	IFS="${oIFS}"
}

updateConf() {
	verbose "Checking ${CA_CERTS_CONF}..."

	if [ ! -f "${CA_CERTS_CONF}" ]; then
		verbose "No such file: ${CA_CERTS_CONF}"
		return
	fi

	backup "${CA_CERTS_CONF}"

	sed -i 							\
		-e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|'	\
		-e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|'\
		"${CA_CERTS_CONF}"

	verbose "${CA_CERTS_CONF} updated."

	verbose "Running update-ca-certificates..."
	update-ca-certificates
	verbose "Done."
}

updateOneBundle() {
	local readonly bundle="${1}"
	local format="PEM"

	verbose "Inspecting '${bundle}'..." 2

	if [ ! -r "${bundle}" ]; then
		# No need to warn, we expect that some
		# of the files won't be readable.
		return
	fi

	if [ ! -f "${bundle}" ]; then
		warn "'${bundle}' is not a regular file."
		return
	fi

	if ! grep -q -- "-----BEGIN CERTIFICATE-----" "${bundle}"; then
		set +e
		<"${bundle}" openssl x509 -inform DER -noout -subject |	\
			grep -q -E "${SUBJECTS_PATTERN}"
		if [ $? -eq 0 ]; then
			warn "Not removing single-cert DER file '${bundle}'."
			echo "${bundle}"
		else
			verbose "${bundle} is clear." 3
		fi
		set -e
		return
	fi

	openssl crl2pkcs7 -nocrl -certfile "${bundle}" 2>/dev/null |	\
		openssl pkcs7 -print_certs -noout 2>/dev/null |		\
		grep ^subject | sort > "${TDIR}/before"
	if ! grep -q -E "${SUBJECTS_PATTERN}" "${TDIR}/before" ; then
		verbose "${bundle} is clear." 3
		rm "${TDIR}/before"
		return
	fi

	if [ x"${DETECT_ONLY}" = x"yes" ]; then
		echo "${bundle}"
		rm "${TDIR}/before"
		return
	fi

	# The universally recommended approach is
	# opportunistic.  It assumes that bundles
	# contain comments in a given format, but that
	# need not be the case.  Instead of relying on
	# that, we actually process each PEM encoded
	# cert, then rebuild the bundle.
	(
	cd "${TDIR}"
	verbose "Splitting ${bundle} into individual files..." 3
	openssl crl2pkcs7 -nocrl -certfile "${bundle}" |	\
		openssl pkcs7 -print_certs | 			\
		awk 'BEGIN { c=0; } 
			/^subject/{ c++; }
			{ f="cert." c ".pem"; print >f; }'
	before=$(ls *.pem | wc -l)
	for f in *.pem; do
		subject="$(<"${f}" openssl x509 -noout -subject | \
				sed -e 's/, /\//g' -e 's/subject= *\/*/\//')"
		fp="$(<"${f}" openssl x509 -noout -sha256 -fingerprint)"
		fpshort="$(echo "${fp}" | 				\
				tr -d ':' | tr '[a-z]' '[A-Z]' |	\
				cut -d= -f2)"

		verbose "Checking CA '${subject}'..." 4
		for chksum in $( echo "${ROOTS}" | sed -e 's/|.*//'); do
			if [ x"${fpshort}" = x"${chksum}" ]; then
				verbose "Removing root ${fp}..." 4
				rm ${f}
				continue 2
			fi
		done
		echo "### ${subject}" >> new-bundle
		echo >> new-bundle
		echo "=== ${subject}" >> new-bundle
		<"${f}" openssl x509 -text -SHA256 -fingerprint >> new-bundle
		echo >> new-bundle
		
	done

	openssl crl2pkcs7 -nocrl -certfile new-bundle |	\
		openssl pkcs7 -print_certs -noout |	\
		grep ^subject | sort > "${TDIR}/after"

	set +e
	diff=$(diff -bu before after | grep -c ^-subject)
	set -e

	rm *.pem before after

	if [ ${diff} -gt 4 ]; then
		error "Almost removed ${diff} certs??"
		# NOTREACHED
	elif [ ${diff} -gt 0 ]; then
		verbose "Removed ${diff} certs." 3
	elif [ ${diff} -eq 0 ]; then
		verbose "No certificates removed." 3
		return
	fi

	verbose "Installing updated ${bundle}..." 3
	backup "${bundle}"
	install -m 0644 new-bundle ${bundle}
	verbose "${bundle} updated."
	)
}

usage() {
	cat <<EOH
Usage: ${PROGNAME} [-Vbhlv] [-d path] [-f file] [-p pip]
        -V       print version number and exit
        -b       create a backup file of any modified bundles
        -d path  detect affected bundles under 'path' without modifying them
        -f file  only prune this CA bundle
        -h       print this help and exit
        -l       enable logging
        -p pip   path to python/pip executable
        -v       be verbose
EOH
}

verbose() {
	local readonly msg="${1}"
	local level="${2:-1}"
	local i=0

	log "${msg}"

	if [ ${level} -le ${VERBOSITY} ]; then
		while [ ${i} -lt ${level} ]; do
			printf "=" >&2
			i=$(( ${i} + 1 ))
		done
		echo "> ${msg}" >&2
	fi
}

warn() {
	local readonly msg="${1}"
	local mtype="${2:-WARNING}"

	echo "${mtype}: ${msg}" >&2
	log "${msg}"
}


###
### Main
###

while getopts 'Vbd:f:hlp:v' opt; do
	case "${opt}" in
		V)
			echo "${PROGNAME} ${VERSION}"
			exit 0
			# NOTREACHED
		;;
		b)
			BACKUP="yes"
		;;
		d)
			p="${OPTARG}"
			DETECT_ONLY="yes"
			if [ -f "${p}" ]; then
				BUNDLE_FILES="${BUNDLE_FILES}
${p}"
			elif [ -d "${p}" ]; then
				SEARCH_PATHS="${SEARCH_PATHS}
${p}"
			else
				error "No such file or directory: ${p}"
				exit 1
				# NOTREACHED
			fi
		;;
		f)
			f="${OPTARG}"
			if [ ! -f "${f}" ]; then
				error "No such file: ${f}"
				exit 1
				# NOTREACHED
			fi
			BUNDLE_FILES="${BUNDLE_FILES}
${f}"
		;;
		h|\?)
			usage
			exit 0
			# NOTREACHED
		;;
		l)
			LOGGING="yes"
		;;
		p)
			PYTHON_PIP="${OPTARG}"
		;;
		v)
			VERBOSITY=$(( ${VERBOSITY} + 1 ))
		;;
		*)
			usage
			exit 1
			# NOTREACHED
	esac
done
shift $(( ${OPTIND} - 1 ))

if [ $# -ne 0 ]; then
	usage
	exit 1
	# NOTREACHED
fi

if [ -n "${PYTHON_PIP}" ]; then
	flag=""
	if [ -n "${BUNDLE_FILES}" ]; then
		flag="-f"
	elif [ -n "${SEARCH_PATHS}" ]; then
		flag="-d"
	fi
	if [ -n "${flag}" ]; then
		error "'${flag}' and '-p' are mutually exclusive."
		# NOTREACHED
	fi
fi

trap cleanup 0

TDIR="$(mktemp -d ${TMPDIR:-/tmp}/emudhra-cleanup.XXXX)"

SUBJECTS_PATTERN="$(echo "${ROOTS}" | sed -e 's/.*|//' | \
			tr '\n' '|' | sed -e 's/^|/(/' -e 's/||/)/')"

verbose "emudhra-cleanup starting..."

if [ -n "${PYTHON_PIP}" ]; then
	fixPip
else
	handleBundles
fi
verbose "emudhra-cleanup complete."
