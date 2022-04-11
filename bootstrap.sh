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
SYL_SSH_KEY_NAME_PREFIX="sylsh"

SYL_GITHUB='github.com'
SYL_GITHUB_KEY_REGISTRATION_URL='https://github.com/settings/ssh/new'
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
		if [ $? -eq 0 ]
		then
			printf '%s\n' "${reply}" |
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
		if [ "${status}" -eq 0 ]
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

syl_run_sylsh_install() {
	(
		cd -- "${SYL_SYLSH_DIR}" >&2 && bin/syl configure
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

syl_select_interactive() {
	(
		# Directly access process TTY
		exec 3</dev/tty 4>/dev/tty
		if [ $? -ne 0 ]
		then
			printf '%s: Unable to access process TTY.\n' \
				'syl_select_interactive' >&2
			exit 2
		fi

		prompt="${1:-" Your option?"}"
		format="${COLOR_CYAN} %d) %s\n${COLOR_RESET}"
		index='0'
		while read -r item
		do
			index=$(($index + 1))
			eval "option_${index}=${item}"
			printf "${format}" "${index}" "${item}" >&4
		done
		[ "${index}" -lt 1 ] && exit 1
		syl_print_info -n "${prompt} [1-${index}] " >&4
		reply=$(syl_prompt <&3)
		if (
			[ $? -eq 0 ] &&
			[ -n "${reply##*[!0-9]*}" ] &&
			[ "${reply}" -ge 1 ] &&
			[ "${reply}" -le "${index}" ]
		)
		then
			eval "printf '%s\n' \"\${option_${reply}}\""
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
			) && (
				printf '%s\n' "${private_key}"
				exit 0
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
			if syl_is_valid_ssh_key "${name}" >&2
			then
				printf 'Valid SSH key found: %s\n' "${name}" >&2
				printf '%s\n' "${name}"
			else
				printf 'Invalid SSH key: %s\n' "${name}" >&2
			fi
		done
	) | sort
}

syl_select_existing_ssh_key_interactive() {
	(
		# Directly access process TTY
		exec 3</dev/tty 4>/dev/tty
		if [ $? -ne 0 ]
		then
			printf '%s: Unable to access process TTY.\n' \
				'syl_select_existing_ssh_key_interactive' >&2
			exit 2
		fi

		syl_print_info -n ' > Searching SSH keys on your system... ' >&4

		# Tiny pause...
		sleep 1

		# Populate local variables with SSH keys info
		ssh_keys=$(syl_get_available_ssh_keys)
		ssh_key_count=$(printf '%s\n' "${ssh_keys}" |
			grep -Ev '^[[:blank:]]*$' |
			wc -l |
			tr -d '[:blank:]')

		if [ "${ssh_key_count}" -gt 1 ]
		then
			# Multiple SSH Keys found
			syl_print_info "${ssh_key_count} keys found!" \
				' > Would you like to use any of them? (Leave empty to create one)' >&4
			selected=$(printf '%s\n' "${ssh_keys}" |
				syl_select_interactive ' > Your option?')
			if [ $? -eq 0 ] && [ -n "${selected}" ]
			then
				syl_print_info " > SSH key \"${selected}\" selected!" >&4
				printf '%s\n' "${selected}"
				exit 0
			fi
		elif [ "${ssh_key_count}" -eq 1 ]
		then
			syl_print_info "${ssh_key_count} key found!" >&4
			syl_print_info -n " > Would you like to use the SSH key named \"${ssh_keys}\"? [Y/n] " >&4
			reply=$(syl_prompt <&3)
			if [ $? -eq 0 ] && ! syl_is_no "${reply}"
			then
				syl_print_info " > SSH key \"${ssh_keys}\" selected!" >&4
				printf '%s\n' "${ssh_keys}"
				exit 0
			fi
		else
			syl_print_info 'None found.' >&4
		fi
		exit 1
	)
}

syl_generate_ssh_key_name() {
	(
		prefix="${SYL_SSH_DIR}/${1:-"${SYL_SSH_KEY_NAME_PREFIX}"}"
		suffix=0
		path="${prefix}"
		while [ -e "${path}" ] || [ -e "${path}.pub" ]
		do
			suffix=$(($suffix + 1))
			path="${prefix}-${suffix}"
		done
		printf '%s\n' "${path##*/}"
	)
}

syl_create_ssh_key_interactive() {
	(
		# Directly access process TTY
		exec 3</dev/tty 4>/dev/tty
		if [ $? -ne 0 ]
		then
			printf '%s: Unable to access process TTY.\n' \
				'syl_create_ssh_key_interactive' >&2
			exit 2
		fi

		syl_print_info \
			" > OK. Let's create a new SSH key pair!" \
			' > In order to create a new SSH key pair you need to provide an email address' \
			'   (which will be used to annotate your public key) and a passphrase (which will ' \
			'   be used to encrypt your private key, keeping it safe from curious eyes).' >&4

		# Get user email
		email=''
		while [ -z "${email}" ]
		do
			syl_print_info -n ' > Enter the email address: ' >&4
			reply=$(syl_prompt_email)
			if [ $? -eq 0 ]
			then
				if [ -z "${reply}" ]
				then
					syl_print_warn ' > Invalid email address...' >&4
					syl_print_info " > Let's try again." >&4
					continue
				fi
				email="${reply}"
				syl_print_info -n " > Confirm usage of email \"${email}\"? [Y/n] " >&4
				reply=$(syl_prompt <&3)
				if [ $? -eq 0 ]
				then
					if syl_is_no "${reply}"
					then
						email=''
						continue
					else
						syl_print_info ' > OK' >&4
						break
					fi
				else
					printf 'Email confirmation aborted...\n' >&2
					syl_print_warn ' > Aborting...' >&4
					exit 1
				fi
			else
				printf 'Email input aborted...\n' >&2
				syl_print_warn ' > Aborting...' >&4
				exit 1
			fi
		done

		# Get passphrase
		passphrase=''
		while [ -z "${passphrase}" ]
		do
			syl_print_info -n ' > Enter the passphrase: ' >&4
			reply=$(syl_prompt_password <&3)
			status="$?"
			echo >&4
			if [ "${status}" -eq 0 ]
			then
				if [ -z "${reply}" ]
				then
					syl_print_warn \
						' > If no passphrase is provided, your private key will be readable by anyone' \
						'   who gains access to your computer!' >&4
					syl_print_info -n ' > Proceed anyway? [y/N] ' >&4
					reply=$(syl_prompt <&3)
					if [ $? -eq 0 ] && syl_is_yes "${reply}"
					then
						break
					fi
					continue
				else
					syl_print_info ' > OK' >&4
					syl_print_info -n ' > Enter the same passphrase again to confirm: ' >&4
					passphrase="${reply}"
					reply=$(syl_prompt_password <&3)
					status="$?"
					echo >&4
					if [ "${status}" -eq 0 ] && [ "X${passphrase}" = "X${reply}" ]
					then
						syl_print_info ' > OK' >&4
						break
					fi
					passphrase=''
					syl_print_warn ' > The passphrases do not match...' >&4
					syl_print_info " > Let's try again." >&4
				fi
			else
				printf 'Passphrase input aborted...\n' >&2
				syl_print_warn ' > Aborting...' >&4
				exit 1
			fi
		done

		# Generate an available key name
		key_name=$(syl_generate_ssh_key_name)

		# Generate SSH Key
		ssh-keygen \
			-t ed25519 \
			-f "${SYL_SSH_DIR}/${key_name}" \
			-C "${email}" \
			-N "${passphrase}" >&2

		if [ $? -ne 0 ]
		then
			printf 'Error generating SSH key pair...\n' >&2
			syl_print_warn ' > Error generating SSH key pair ...' >&4
			exit 2
		fi

		syl_print_info " > SSH key \"${key_name}\" successfully created!" >&4

		printf '%s\n' "${key_name}" "${passphrase}"
		exit 0
	)
}

syl_add_ssh_key_to_agent() {
	(
		key="$1"
		pass="$2"
		if syl_is_valid_command 'expect'
		then
			expect >&2 << EOF
spawn ssh-add "${key}"
expect "Enter passphrase"
send "${pass}\n"
expect eof
EOF
			if [ $? -eq 0 ]
			then
				printf 'SSH key successfully added to SSH agent: %s\n' \
					"${key}" >&2
				exit 0
			fi
		fi
		exit 2
	)
}

syl_add_ssh_key_to_agent_interactive() {
	(
		# Directly access process TTY
		exec 3</dev/tty 4>/dev/tty
		if [ $? -ne 0 ]
		then
			printf '%s: Unable to access process TTY.\n' \
				'syl_add_ssh_key_to_agent_interactive' >&2
			exit 2
		fi

		if [ $# -gt 1 ]
		then
			key="$1"
			pass="$2"
		elif [ $# -gt 0 ]
		then
			key="$1"
			pass=''
		else
			printf 'Aborting due to no SSH key name provided by the user...\n' >&2
			syl_print_warn " > No SSH key name provided..." >&4
			exit 1
		fi

		key_path=$(syl_is_valid_ssh_key "${key}")
		if [ $? -ne 0 ] || [ -z "${key_path}" ]
		then
			printf 'Aborting due to no valid SSH key name provided by the user...\n' >&2
			syl_print_warn " > No valid SSH key name provided..." >&4
			exit 1
		fi

		public_key=''
		attempts=0
		while true
		do
			public_key=$(ssh-keygen -y -f "${key_path}" -P "${pass}")
			if [ $? -eq 0 ] || [ -n "${public_key}" ]
			then
				[ "${attempts}" -gt 0 ] && syl_print_info " > OK" >&4
				break
			elif [ "${attempts}" -lt 3 ]
			then
				[ "${attempts}" -gt 0 ] && syl_print_warn " > Invalid passphrase..." >&4
				attempts=$(($attempts + 1))
				syl_print_info -n " > Please enter the passphrase for key \"${key}\": " >&4
				reply=$(syl_prompt_password <&3)
				status="$?"
				echo >&4
				if [ "${status}" -eq 0 ]
				then
					pass="${reply}"
					continue
				else
					printf 'Passphrase input aborted when adding key to SSH agent...\n' >&2
					syl_print_warn ' > Aborting...' >&4
					exit 1
				fi
			else
				printf 'No valid password provided in multiple attempts...\n' >&2
				syl_print_warn " > No valid password provided in multiple attempts..." >&4
				exit 2
			fi
		done

		if ! syl_add_ssh_key_to_agent "${key_path}" "${pass}"
		then
			printf 'Error adding key to SSH agent...\n' >&2
			syl_print_warn ' > Error adding key to SSH agent...' >&4
			exit 2
		fi

		syl_print_info \
			" > The SSH key \"${key}\" has been successfully added to your SSH agent." \
			" > Before proceeding, please make sure you have successfully registered the" \
			"   following public key to your GitHub account and that you have access to" \
			"   Syllable's private repositories." \
			'' \
			" > GitHub Key Registration URL:" >&4
		syl_print_warn \
			"   ${SYL_GITHUB_KEY_REGISTRATION_URL}" \
			'' >&4
		syl_print_info \
			" > Public Key:" >&4
		syl_print_warn \
			"   ${public_key}" \
			'' >&4

		(
			# Offer help to register SSH key on GitHub (isolated in a subshell)
			syl_print_info -n ' > Would you like to register it right now? [y/N] ' >&4
			reply=$(syl_prompt <&3)
			if [ $? -eq 0 ] && syl_is_yes "${reply}"
			then
				syl_print_info ' > OK' >&4
				syl_is_valid_command 'pbcopy' && (
					printf '%s\n' "${public_key}" | pbcopy && (
						syl_print_info \
							' > Your public key has been copied to your clipboard!' >&4
						syl_is_valid_command 'open' && (
							syl_print_info \
								' > If your browser does not show up shortly, please access the URL above' \
								'   and paste your public key in the "key" field of the form.' >&4
							sleep 4
							open -u "${SYL_GITHUB_KEY_REGISTRATION_URL}"
							exit 0
						) || (
							syl_print_info \
								' > Please access the URL above and paste your public key in the "key" field' \
								'   of the form.' >&4
							exit 0
						)
					)
				) || (
					syl_print_info \
						' > Please copy your public key, access the URL above and paste it' \
						'   in the "key" field of the form.' >&4
				)
				syl_print_info -n ' > Press return when you are ready to proceed.' >&4
				syl_prompt >/dev/null <&3
				syl_print_info ' > OK' >&4
			fi
		)

		exit 0
	)
}

syl_ssh_auth() {
	(
		selected_ssh_key=$(syl_select_existing_ssh_key_interactive)
		status="$?"
		if [ "${status}" -eq 0 ] && [ -n "${selected_ssh_key}" ]
		then
			syl_add_ssh_key_to_agent_interactive "${selected_ssh_key}"
		else
			if [ "${status}" -gt 1 ]
			then
				printf 'Unexpected error while trying to select existing SSH keys...\n' >&2
			fi
			created_ssh_key=$(syl_create_ssh_key_interactive)
			status="$?"
			if [ "${status}" -eq 0 ] && [ -n "${created_ssh_key}" ]
			then
				printf '%s\n' "${created_ssh_key}" | (
					if read -r key && read -r passphrase && [ -n "${key}" ]
					then
						syl_add_ssh_key_to_agent_interactive "${key}" "${passphrase}"
					else
						printf 'Error reading attributes from new SSH key...\n' >&2
						syl_print_warn ' > Unexpected error while reading attribures from new SSH key...'
						exit 2
					fi
				)
			else
				if [ "${status}" -gt 1 ]
				then
					printf 'Unexpected error while trying to create a new SSH keys...\n' >&2
					exit 2
				fi
				printf 'Aborted creation of a new SSH keys...\n' >&2
				exit 1
			fi
		fi
	)
}

syl_install_sylsh() {
	(
		syl_check_required_utilities \
			'ssh-add' \
			'ssh-keygen' \
			'ssh-keyscan' \
			'expect' \
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

			syl_ssh_auth
			status="$?"
			if [ "${status}" -ne 0 ]
			then
				if [ "${status}" -gt 1 ]
				then
					printf 'Error authenticating user SSH key...\n' >&2
					syl_print_warn ' > Error authenticating user SSH key...'
					exit 2
				fi
				printf 'Authentication aborted by the user...\n' >&2
				syl_print_warn ' > Authentication aborted...'
				exit 1
			fi

			syl_print_info \
				'' \
				' > Cloning SYLSH...'
			if ! syl_clone_sylsh
			then
				printf 'Error cloning SYLSH repository...\n' >&2
				syl_print_warn ' > Error cloning SYLSH repository...'
				exit 2
			fi
			syl_print_info ' > OK'
		fi

		syl_print_info \
			'' \
			'' \
			' > Preparing to configure SYLSH...' \
			'' \
			'' \
			'' \
			''

		sleep 1

		syl_run_sylsh_install
		status="$?"
		if [ "${status}" -ne 0 ]
		then
			printf 'Error running configure action from sylsh utility: %s\n' \
				"${status}" >&2
		fi

		syl_print_info \
			'' \
			' > Installation finished!'
		exit 0
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
			echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' |
				tee -a "${HOME}/.zprofile" "${HOME}/.bash_profile" >/dev/null

			eval "$(/opt/homebrew/bin/brew shellenv)"
			ask_restart_terminal='1'
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
				syl_is_valid_command 'open' && open -j "${SYL_DOCKER_DESKTOP_APP}"
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
				ask_restart_terminal='1'
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

		if [ -n "${ask_restart_terminal}" ]
		then
			syl_print_warn \
				' > The installation process has made changes to your environment and' \
				'   your terminal needs to be restarted. Please close your current terminal' \
				'   and reopen it for changes to take effect.'
		fi
	)
}

# Entry Point

if touch "${SYL_LOG}" >/dev/null 2>&1
then
	exec 2>"${SYL_LOG}"
fi
syl_main "$@"
