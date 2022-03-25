#!/bin/sh

# Main Constants

SYL_TMP='/tmp'
SYL_RUNID="$(date '+%Y%m%d%H%M%S')-$(printf '%06d' "$$")"
SYL_LOG="${SYL_TMP}/dev-bootstrap-${SYL_RUNID}.log"
SYL_GIT_DIR="${HOME}/git/syllable"
SYL_SYLSH_DIR="${SYL_GIT_DIR}/sylsh"
SYL_DOCKER_DESKTOP_APP='/Applications/Docker.app'

GITHUB='github.com'
SYLSH_GIT_PATH='asksyllable/sylsh.git'

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
		format='%s'
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

syl_ensure_accessible_dir() {
	(
		dir="$1"
		if [ "X${dir}" = 'X-c' ]; then
			dir="$2"
			if [ -n "${dir}" ] && [ ! -e "${dir}" ]; then
				if ! mkdir -p -m 'u=rwx,g=rx,o=rx' "${dir}" >/dev/null 2>&1; then
					exit 1
				fi
			fi
		fi
		test -n "${dir}" && test -d "${dir}" && test -r "${dir}" && test -x "${dir}"
	)
}

syl_print_unrecoverable_install_error() {
	(
		app_name="$1"
		syl_print_error \
			'Bad news...' \
			"It looks like \"${app_name}\" could not be properly installed and" \
			'the setup process cannot proceed without it.'
			'Please contact support at "itsupport@syllable.ai".' \
			''
	)
}

syl_is_macOS() {
	(
		uname -s | grep -q '^Darwin'
	)
}

syl_is_arm64() {
	(
		uname -s | grep -q '^arm64'
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

syl_is_sylsh_installed() {
	(
		cd -- "${SYL_SYLSH_DIR}" >&2 && git status >&2 && "${SYL_SYLSH_DIR}/bin/syl" version >&2
	)
}

syl_clone_sylsh() {
	(
		! syl_is_sylsh_installed &&
		cd -- "$(dirname -- "${SYL_SYLSH_DIR}")" >&2 &&
		ssh-keyscan -H "${GITHUB}" >> ~/.ssh/known_hosts &&
		git clone "git@${GITHUB}:${SYLSH_GIT_PATH}" "$(basename -- "${SYL_SYLSH_DIR}")" >&2 ||
		exit 1
	)
}

syl_get_available_ssh_keys() {
	find "${HOME}/.ssh" -type f -iname '*.pub' | (
		while read -r file
		do
			name="${file##*'/'}"
			name="${name%'.pub'}"
			printf 'Found SSH key: %s\n' "${name}" >&2
			printf '%s\n' "${name}"
		done
	)
}

syl_select() {
	printf '%s\n' "$1" | (
		index='1'
		while read -r item
		do
			printf ' %02d) %s\n' "${index}" "${item}"
			index=$(($index + 1))
		done
	)
}

syl_install_sylsh() {
	if ! syl_clone_sylsh; then
		syl_print_info \
			'SYLSH is a Syllable private repository and you need permissions to access' \
			'its contants.'
		ssh_keys=$(syl_get_available_ssh_keys)
		if [ -n "${ssh_keys}" ]; then
			syl_select "${ssh_keys}"
			exit 1
		else
			syl_print_info -n 'Would you like to create an SSH key now? [Y/n] '
			reply=$(syl_prompt)
			if syl_is_no "${reply}"; then
				syl_print_info 'OK. Aborting installation of syl.sh utility...'
				exit 1
			fi
			syl_print_info 'OK.' 'What is your email address?'
			reply=$(syl_prompt)
			ssh-keygen -t ed25519 -C "${reply}" -f "${HOME}/.ssh/sylsh" -N ''
		fi
	fi
}

syl_main() {
	(
		# TODO: Check basic-utility requirements
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
				syl_print_unrecoverable_install_error 'Homebrew'
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
			syl_print_info '[v] Homebrew is already installed!'
		else
			syl_print_unrecoverable_install_error 'Homebrew'
			exit 1
		fi

		# How about git?
		if syl_is_valid_command -v 'git'
		then
			syl_print_info '[v] Git is already installed!'
		else
			syl_print_unrecoverable_install_error 'Git'
			exit 1
		fi

		# Default Git Repository
		if syl_ensure_accessible_dir -c "${SYL_GIT_DIR}" && test -w "${SYL_GIT_DIR}"
		then
			syl_print_info "[v] Git repositories folder at: ${SYL_GIT_DIR}"
		else
			syl_print_unrecoverable_install_error 'Git'
			exit 1
		fi

		# How about Rosetta 2?
		if syl_is_arm64
		then
			if softwareupdate --install-rosetta --agree-to-license >&2
			then
				syl_print_info '[v] Rosetta 2 is already installed!'
			else
				syl_print_warn '[x] Rosetta could not be installed...'
			fi
		fi

		# How about Docker Desktop App?
		if [ -e "${SYL_DOCKER_DESKTOP_APP}" ]
		then
			syl_print_info '[v] Docker Desktop is already installed!'
		else
			syl_print_info \
				'Installing Docker Desktop...' \
				''
			if brew install --cask docker >&2
			then
				syl_print_info '[v] Docker Desktop successfully installed!'
			else
				syl_print_warn \
					'[x] Something went wrong while installing Docker Desktop...' \
					'    Please request support at "itsupport@syllable.ai" and provide the following' \
					"    log file with error details: \"${SYL_LOG}\"". \
					'    Or you can try a manual install at "https://docs.docker.com/desktop/mac/install/".' \
					''
			fi
		fi

		# Install syl.sh
		if syl_is_sylsh_installed
		then
			syl_print_info '[v] syl.sh is already installed!'
		else
			syl_install_sylsh
			result="$?"
			if [ "${result}" -eq 0 ]
			then
				syl_print_info '[v] syl.sh successfully installed!'
			elif [ "${result}" -eq 1 ]
			then
				syl_print_info '[x] syl.sh installation aborted by the user.'
			else
				syl_print_warn \
					'[x] Something went wrong while installing the "syl.sh" utility...' \
					'    Please request support at "itsupport@syllable.ai" and provide the following' \
					"    log file with error details: \"${SYL_LOG}\"". \
					''
			fi
		fi
	)
}

# Entry Point

touch "${SYL_LOG}" >/dev/null 2>&1 && exec 2>"${SYL_LOG}"
syl_main "$@"
