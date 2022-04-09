#!/usr/bin/env bash

# Main Constants

SYL_TMP='/tmp'
SYL_RUNID="$(date '+%Y%m%d%H%M%S')-$(printf '%06d' "$$")"
SYL_LOG="${SYL_TMP}/dev-bootstrap-${SYL_RUNID}.log"
SYL_GIT_DIR="${SYL_GIT_DIR:-"${HOME}/git/syllable"}"
SYL_SYLSH_DIR="${SYL_SYLSH_DIR:-"${SYL_GIT_DIR}/sylsh"}"
SYL_DOCKER_DESKTOP_APP='/Applications/Docker.app'
SYL_SSH_DIR="${HOME}/.ssh"
SYL_SSH_KNOWN_HOSTS="${SYL_SSH_DIR}/known_hosts"
SYL_SSH_KEY_NAME="sylsh"

SYL_GITHUB='github.com'
SYL_SYLSH_GIT_PATH='asksyllable/sylsh.git'

DEFAULT_HOMEBREW_URL='https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
HOMEBREW_URL="${HOMEBREW_URL:-"${DEFAULT_HOMEBREW_URL}"}"

if printf '%s\n' "${LC_CTYPE}" | grep -Eiq '\butf-8\b'
then
	CHECK=$(printf '\342\234\223')
	CROSS=$(printf '\342\234\227')
else
	CHECK='v'
	CROSS='x'
fi

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

syl_prompt_email() {
	(
		reply=$(syl_prompt)
		if [ $? -eq 0 ] && [ -n "${reply}" ]
		then
			printf '%s' "${reply}" |
			sed -En '1s/^[[:space:]]*([[:graph:]]+@[[:graph:]]+)[[:space:]]*$/\1/p'
			exit 0
		fi
		exit 1
	)
}

syl_prompt_password() {
	(
		stty -echo
		read -r password
		status="$?"
		stty echo
		if [ "${status}" -eq 0 ] && [ -n "${password}" ]
		then
			printf '%s\n' "${password}"
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
			'Please contact IT support.' \
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
		if command -v -- "${command}" >/dev/null 2>&1
		then
			if [ -n "${check_version}" ]
			then
				command -- "${command}" --version >/dev/null 2>&1 || exit 1
			fi
			exit 0
		fi
		exit 1
	)
}

syl_is_sylsh_installed() {
	(
		syl_is_valid_command 'syl'
	)
}

syl_update_known_hosts() {
	(
		host="$1"
		known_hosts="${SYL_SSH_KNOWN_HOSTS}"
		ssh-keyscan "${host}" >>"${known_hosts}" && (
			# Attempt to remove duplicates from known_hosts ignoring failure
			sort -u -o "${known_hosts}" "${known_hosts}" >&2
			exit 0
		)
	)
}

syl_is_sylsh_cloned() {
	(
		sylsh_exec="syl.sh"
		cd -- "${SYL_SYLSH_DIR}" >&2 &&
		test -n "$(git tag --list 'v0.1.0')" &&
		test -f "${sylsh_exec}" &&
		test -x "${sylsh_exec}"
	)
}

syl_clone_sylsh() {
	(
		syl_is_sylsh_cloned || (
			sylsh_parent_dir=$(dirname -- "${SYL_SYLSH_DIR}")
			sylsh_dir_name=$(basename -- "${SYL_SYLSH_DIR}")
			syl_ensure_accessible_dir -c "${sylsh_parent_dir}" &&
			test -w "${sylsh_parent_dir}" &&
			cd -- "${sylsh_parent_dir}" >&2 &&
			syl_update_known_hosts "${SYL_GITHUB}" &&
			git clone "git@${SYL_GITHUB}:${SYL_SYLSH_GIT_PATH}" "${sylsh_dir_name}" >&2
		)
	)
}

syl_select() {
	(
		options="$1"
		prompt="${2:-" Your option?"}"
		printf '%s\n' "${options}" | (
			format=' %d) %s\n'
			if [ -t 4 ]; then
				format="${COLOR_CYAN}${format}${COLOR_RESET}"
			fi
			index='0'
			while read -r item
			do
				index=$(($index + 1))
				printf "${format}" "${index}" "${item}" >&4
			done
			[ "${index}" -lt 1 ] && exit 1
			syl_print_info -n "${prompt} [1-${index} or just press enter for none] " >&4
			reply=$(syl_prompt <&3)
			if [ "${reply}" -ge 1 ] && [ "${reply}" -le "${index}" ]
			then
				printf '%s\n' "${options}" | sed -n "${reply}p"
				exit 0
			fi
			exit 1
		)
	)
}

syl_test_select() {
	(
		exec 3<&0 4>&1
		reply=$(syl_select "$1")
		if [ $? -eq 0 ]
		then
			syl_print_info " Selected: ${reply}"
			exit 0
		fi
		exit 1
	)
}

syl_check_required_utilities() {
	(
		result='0'
		missing=''
		while [ $# -gt 0 ]
		do
			utility="$1"
			shift 1
			if ! command -v -- "${utility}" >/dev/null 2>&1
			then
				missing="${missing}, ${utility}"
				result='1'
			fi
		done
		missing="${missing#', '}"
		if [ -n "${missing}" ]
		then
			printf 'Missing required utilities: %s\n' \
				"${missing}" >&2
			syl_print_warn " > Missing required utilities: ${missing}"
		fi
		exit "${result}"
	)
}

syl_is_valid_ssh_key() {
	(
		key_name="$1"
		[ -n "${key_name}" ] && (
			private_key="${SYL_SSH_DIR}/${key_name}"
			public_key="${private_key}.pub"
			(
				test -f "${private_key}" &&
				test -r "${private_key}" &&
				test -f "${public_key}" &&
				test -r "${public_key}" &&
				ssh-keygen -l -f "${public_key}" >&2
			)
		)
	)
}

syl_select_ssh_key() {
	(
		key_name="$1"
		syl_is_valid_ssh_key "${key_name}" && (
			sylsh_key_name="${SYL_SSH_KEY_NAME}"
			[ "${key_name}" == "${sylsh_key_name}" ] || (
				key_path="${SYL_SSH_DIR}/${key_name}"
				sylsh_key_path="${SYL_SSH_DIR}/${sylsh_key_name}"
				# Create hard links
				ln -f "${key_path}" "${sylsh_key_path}" &&
				ln -f "${key_path}.pub" "${sylsh_key_path}.pub"
			)
		)
	)
}

syl_get_available_ssh_keys() {
	(
		for entry in "${SYL_SSH_DIR}"/*.pub
		do
			name="${entry##*'/'}"
			name="${name%'.pub'}"
			if syl_is_valid_ssh_key "${name}"
			then
				printf 'Valid SSH key found: %s\n' "${name}" >&2
				printf '%s\n' "${name}"
			else
				printf 'Invalid SSH key: %s\n' "${name}" >&2
			fi
		done
	) | sort
}

syl_prepare_ssh_key() {
	(
		if ! syl_is_valid_ssh_key "${SYL_SSH_KEY_NAME}"
			syl_print_info -n ' > Searching SSH keys on your system... '
			sleep 1

			# Populate local variables with SSH keys info
			ssh_keys=$(syl_get_available_ssh_keys)
			ssh_key_count=$(printf '%s\n' "${ssh_keys}" |
				grep -Ev '^[[:blank:]]*$' |
				wc -l |
				tr -d '[:blank:]')

			(
				# Multiple SSH Keys found
				[ "${ssh_key_count}" -gt 1 ] || exit 1
				syl_print_info "${ssh_key_count} keys found!"
				# syl_select requires the additional #3 and #4 file descriptors mapped to
				# STDIN and STDOUT respectively
				exec 3<&0 4>&1
				selected=$(syl_select "${ssh_keys}" ' > Which one would you like to use?')
				[ $? -eq 0 ] && [ -n "${selected}" ] && (
					syl_select_ssh_key "${selected}" || (
						printf 'Error selecting one of multiple SSH keys: %s\n' "${selected}" >&2
						exit 2
					)
				)
			) || (
				# A single SSH key was found
				[ $? -gt 1 ] && exit 2
				[ "${ssh_key_count}" -eq 1 ] || exit 1
				syl_print_info "${ssh_key_count} key found!"
				syl_print_info -n " > Would you like to use the SSH key \"${ssh_keys}\"? [Y/n] "
				reply=$(syl_prompt)
				[ $? -eq 0 ] && ! syl_is_no "${reply}" && (
					syl_select_ssh_key "${ssh_keys}" || (
						printf 'Error selecting unique SSH key found: %s\n' "${selected}" >&2
						exit 2
					)
				)
			) || (
				# No SSH was found or none was selected
				[ $? -gt 1 ] && exit 2
				[ "${ssh_key_count}" -eq 0 ] && syl_print_info 'None found.'
				syl_print_info
					" > OK. Let's create one!" \
					" > In order to create a SSH key you need to provide an email address and a passphrase." \
					" > Let's begin with the email address!"

				# Get user email
				email=''
				while [ -z "${email}" ]
				do
					syl_print_info -n " > Which email address would you like to use? "
					reply=$(syl_prompt_email)
					if [ $? -eq 0 ] && [ -n "${reply}" ]
					then
						email="${reply}"
						syl_print_info -n " > Confirm usage of email \"${email}\"? [Y/n] "
						reply=$(syl_prompt)
						if [ $? -eq 0 ]
						then
							if syl_is_no "${reply}"
							then
								email=''
								continue
							else
								syl_print_info ' > OK.'
								break
							fi
						else
							printf 'Aborted by user due to invalid input for email confirmation...\n'
							syl_print_info ' > Aborting...'
							exit 1
						fi
					else
						printf 'Aborted by user due to invalid input for email...\n'
						syl_print_info ' > Aborting...'
						exit 1
					fi
				done

				# Get passphrase
				passphrase=''
				while [ -z "${passphrase}" ]
				do
				done

				# Generate SSH Key
				ssh-keygen \
					-t ed25519 \
					-C "${email}" \
					-f "${SYL_SSH_DIR}/${SYL_SSH_KEY_NAME}" \
					-N "${passphrase}" >&2 || exit 2

			) || exit $?
		fi
	)
}

syl_install_sylsh() {
	(
		syl_check_required_utilities \
			'ssh-keygen' \
			'ssh-add' \
			'ssh-keyscan' \
			'git' || exit 2

		if ! syl_clone_sylsh;
		then
			syl_print_info \
				' > The SYLSH utility is a private Syllable project and special permissions' \
				'   are needed to access its contents.' \
				' > Before proceeding, please make sure you have a an active GitHub account' \
				'   and that you are a member of the Syllable Developers group.'
			syl_print_info -n ' > Continue? [Y/n] '
			reply=$(syl_prompt)
			syl_is_no "${reply}" && exit 1
			echo
			( syl_prepare_ssh_key && ( syl_clone_sylsh || exit 2 ) ) || exit $?
		fi
	)
}

syl_print_log_tail_command() {
	(
		syl_print_info \
			' > See what is happening behind the scenes by typing the following command' \
			'   in another terminal:'
		syl_print_warn \
			"   tail -f '${SYL_LOG}'"
	)
}

syl_main() {
	(
		# Option to run internal commands -- Useful for testing
		if [  "X$1" = 'X--run-internal' ] && [ $# -gt 1 ]
		then
			command="$2"
			shift 2
			if (
				printf '%s\n' "${command}" | grep -Eq '^syl_[[:alnum:]_]+$' &&
				syl_is_valid_command "${command}"
			)
			then
				"${command}" "$@"
				exit $?
			else
				syl_print_error 'Invalid internal command.'
				exit 1
			fi
		fi

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
			'' \
			'This script will attempt to install a minimal set of applications' \
			'which are required for regular developer activities.' \
			''

		syl_print_info -n 'Continue? (It is safe to run this script multiple times) [Y/n] '
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
			syl_print_info "[${CHECK}] Homebrew is already installed!"
		else
			syl_print_unrecoverable_install_error 'Homebrew'
			exit 1
		fi

		# How about git?
		if syl_is_valid_command -v 'git'
		then
			syl_print_info "[${CHECK}] Git is already installed!"
		else
			syl_print_unrecoverable_install_error 'Git'
			exit 1
		fi

		# Default Git Repository
		if syl_ensure_accessible_dir -c "${SYL_GIT_DIR}" && test -w "${SYL_GIT_DIR}"
		then
			syl_print_info "[${CHECK}] Git repositories folder at: ${SYL_GIT_DIR}"
		else
			syl_print_unrecoverable_install_error 'Git'
			exit 1
		fi

		# How about Rosetta 2?
		if syl_is_arm64
		then
			if softwareupdate --install-rosetta --agree-to-license >&2
			then
				syl_print_info "[${CHECK}] Rosetta 2 is already installed!"
			else
				syl_print_warn "[${CROSS}] Rosetta could not be installed..."
			fi
		fi

		# How about Docker Desktop App?
		if [ -e "${SYL_DOCKER_DESKTOP_APP}" ]
		then
			syl_print_info "[${CHECK}] Docker Desktop is already installed!"
		else
			syl_print_info \
				'Installing Docker Desktop...' \
				''
			if (
				exec 2>&1
				brew install --cask docker
			)
			then
				syl_print_info "[${CHECK}] Docker Desktop successfully installed!"
			else
				syl_print_warn \
					"[${CROSS}] Something went wrong while installing Docker Desktop..." \
					'    Please contact IT support and provide the following file' \
					"    with error details: \"${SYL_LOG}\"". \
					'    You can try a manual install at "https://docs.docker.com/desktop/mac/install/".' \
					''
			fi
		fi

		# Check if Ansible is installed
		if syl_is_valid_command -v 'ansible'
		then
			syl_print_info "[${CHECK}] Ansible is already installed!"
		else
			echo
			syl_print_info -n ' > Would you like to install Ansible? [Y/n] '
			reply=$(syl_prompt)
			echo
			if ! syl_is_no "${reply}"
			then
				syl_print_info \
					'Installing Ansible...' \
					''
				if (
					exec 2>&1
					brew install ansible
				)
				then
					syl_print_info "[${CHECK}] Ansible successfully installed!"
				else
					syl_print_warn \
						"[${CROSS}] Something went wrong while installing Ansible..." \
						'    Please contact IT support and provide the following file' \
						"    with error details: \"${SYL_LOG}\"". \
						''
				fi
			else
				syl_print_warn "[${CROSS}] Ansible installation skipped by the user."
			fi
		fi

		# Install syl.sh
		if syl_is_sylsh_installed
		then
			syl_print_info "[${CHECK}] syl.sh is already installed!"
		else
			syl_print_info \
				'Installing SYLSH Utility...' \
				''

			syl_install_sylsh
			result="$?"
			if [ "${result}" -eq 0 ]
			then
				syl_print_info "[${CHECK}] syl.sh successfully installed!"
			elif [ "${result}" -eq 1 ]
			then
				syl_print_warn "[${CROSS}] syl.sh installation aborted by the user."
			else
				syl_print_warn \
					"[${CROSS}] Something went wrong while installing the \"syl.sh\" utility..." \
					'    Please contact IT support and provide the following file' \
					"    with error details: \"${SYL_LOG}\"". \
					''
			fi
		fi
	)
}

# Entry Point

touch "${SYL_LOG}" >/dev/null 2>&1 && exec 2>"${SYL_LOG}"
syl_main "$@"
