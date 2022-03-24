#!/bin/sh

# Main Constants

SYL_TMP='/tmp'
SYL_RUNID="$(date '+%Y%m%d%H%M%S')-$(printf '%06d' "$$")"
SYL_LOG="${SYL_TMP}/dev-bootstrap-${SYL_RUNID}.log"

DEFAULT_HOMEBREW_URL='https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
HOMEBREW_URL="${HOMEBREW_URL:-"${DEFAULT_HOMEBREW_URL}"}"


# Colors

COLOR_GREEN='\033[0;32m'
COLOR_CYAN='\033[0;36m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

# Helpers

syl_print_info() {
	(
		format='%s'
		if [ -t 1 ]; then
			format="${COLOR_CYAN}${format}${COLOR_RESET}"
		fi
		if [ "X$1" = 'X-n' ]; then
			shift 1
			printf "${format}" "$@"
		else
			printf "${format}\n" "$@"
		fi
		exit 0
	)
}

syl_print_warn() {
	(
		format='> %s'
		if [ -t 1 ]; then
			format="${COLOR_YELLOW}${format}${COLOR_RESET}"
		fi
		printf "${format}\n" "$@"
		exit 0
	)
}

syl_print_error() {
	(
		if [ -t 1 ]; then
			header="${COLOR_RED}ERROR:${COLOR_RESET}\n"
			format="${COLOR_RED}  %s${COLOR_RESET}\n"
		else
			header='ERROR:\n'
			format='  %s\n'
		fi
		printf "${header}"
		printf "${format}" "$@"
		exit 0
	)
}

syl_prompt() {
	(
		if read -r reply
		then
			printf '%s\n' "${reply}"
			exit 0
		fi
		exit 1
	)
}

syl_is_yes() {
	(
		reply=$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')
		test "X${reply}" = 'Xy' || test "X${reply}" = 'Xyes'
	)
}

syl_is_no() {
	(
		reply=$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')
		test "X${reply}" = 'Xn' || test "X${reply}" = 'Xno'
	)
}

syl_is_macOS() {
	(
		uname -s | grep -q '^Darwin'
	)
}

syl_is_valid_command() {
	(
		check_version=''
		if [ "X$1" = 'X-v' ]
		then
			shift 1
			check_version='1'
		fi
		command="$1"
		if command -v "${command}" >/dev/null
		then
			if [ -n "${check_version}" ]
			then
				"${command}" --version >/dev/null 2>&1 && exit 0 || exit 1
			fi
			exit 0
		fi
		exit 1
	)
}

syl_main() {
	(
		if ! syl_is_macOS
		then
			syl_print_error \
				'Sorry! This script only works for macOS...' \
				'Bye!' \
				''
			exit 1
		fi

		syl_print_info \
			'' \
			'Welcome to Syllable Developer Setup Utility!' \
			''
			'This script will install a minimal set of applications which are required for' \
			'regular developer activities.' \
			''

		syl_print_info -n 'Proceed with installation? [Y/n] '
		reply=$(syl_prompt)
		if syl_is_no "${reply}"
		then
			syl_print_info \
				'OK... Bye!' \
				''
			exit 1
		fi

		syl_print_info \
			"Great! Let's begin!" \
			''

		if ! syl_is_valid_command 'brew'
		then
			syl_print_info \
				'Installing Homebrew...' \
				''

			if ! (
				# Make STDERR == STDOUT when installing Homebrew
				exec 2>&1
				/bin/bash -c "$(curl -fsSL "${HOMEBREW_URL}")"
			)
			then
				syl_print_error \
					'Bad news ahead...' \
					'Homebrew installation failed and setup process cannot proceed without it.' \
					'Please contact itsupport@syllable.ai for support.' \
					''
				exit 1
			fi

			# Save shellenv in 
			echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' \
				| tee -a "${HOME}/.zprofile" "${HOME}/.bash_profile" >/dev/null

			eval "$(/opt/homebrew/bin/brew shellenv)"
		fi

		# Double-check if Homebrew has been correctly installed
		if syl_is_valid_command -v 'brew'
		then
			syl_print_info 'Good news: Homebrew is already installed!'
		else
			syl_print_error \
				'Bad news ahead...' \
				'It looks like Homebrew is not properly installed and the setup process cannot' \
				'proceed without it.'
				'Please contact itsupport@syllable.ai for support.' \
				''
			exit 1
		fi

		# How about git?
		if syl_is_valid_command -v 'git'
		then
			syl_print_info 'Good news: Git is already installed!'
		else
			syl_print_error \
				'Bad news ahead...' \
				'It looks like Git is not properly installed and the setup process cannot' \
				'proceed without it.'
				'Please contact itsupport@syllable.ai for support.' \
				''
			exit 1
		fi

	)
}

# Entry Point

touch "${SYL_LOG}" >/dev/null 2>&1 && exec 2>"${SYL_LOG}"
syl_main "$@"
