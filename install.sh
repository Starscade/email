#!/bin/sh

test $(basename "$0") = 'install.sh' && {
	INSTALL_DIR=~/.local/bin
	test -n "$1" && test -d "$1" \
		&& INSTALL_DIR="$1"
	INSTALL_PATH="${INSTALL_DIR}/email"
	mkdir -p "$INSTALL_DIR" \
	&& cp -i "$0" "$INSTALL_PATH" \
	&& chmod -v 0755 "$INSTALL_PATH"
	exit
}

_print() {
	printf "\n \033[1;${2}m${1}\033[0m${3}\n\n"
}

extract_address() {
	echo "$1" | sed 's/.*<\(.*\)>/\1/'
}

extract_displayname() {
	echo "$1" | sed 's/\(.*\) <.*>/\1/'
}

panic() {
	_print ERR 31 ": ${1}"
	exit 1
}

print_ok() {
	_print OK 32 "  ${1}"
}

print_sent() {
	_print SENT 32
}

rfc_2047() {
	DISPLAY_NAME="$(extract_displayname "$1")"
	ENCODED="$(printf '%s' "$DISPLAY_NAME" \
		| base64 | tr -d '\n'
	)"
	printf '=?UTF-8?B?%s?=' "$ENCODED"
}

to_base64() {
	printf '%s' "$1" | base64
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--version)
			VERSION='v0.1.0 (main)'
			echo "$VERSION"
			exit
			;;
		--uninstall)
			rm -iv "$0"
			exit
			;;
		--update)
			curl -fLsSo "$(command -v "$0")" \
				'https://email.angus.sh/install.sh' \
				&& print_ok "\033[1m$($(command -v "$0") --version)\033[0m" \
				|| panic 'Upgrade failed!'
			exit
			;;
		--env)
			DOTENV_FILE="$2"
			test -s "$DOTENV_FILE" && {
				set -a
				. "$DOTENV_FILE"
				set +a
			} || panic "Failed to load \"${DOTENV_FILE}\"."
			shift 2
			;;
		--from)
			MAIL_FROM="$2"
			shift 2
			;;
		--to)
			MAIL_TO="$2"
			shift 2
			;;
		--subject)
			MAIL_SUBJECT="$2"
			shift 2
			;;
		--body)
			if test -s "$2"; then
				MAIL_BODY="$(cat "$2")"
			else
				MAIL_BODY="$2"
			fi
			shift 2
			;;
		--attach)
			test -s "$2" || panic 'No file!'
			MAIL_ATTACHMENT_DATA="$(base64 "$2")"
			MAIL_ATTACHMENT_MIME_TYPE="$(
				file -b --mime-type "$2" 2>/dev/null \
				|| echo "text/plain"
			)"
			MAIL_ATTACHMENT_NAME="$(basename "$2")"
			shift 2
			;;
		--read)
			READ_MAIL=1
			shift 2
			;;
		*)
			panic "\033[1m${1}\033[0m is not a recognized argument."
			;;
	esac
done

test -z "$SMTP_USER" && panic 'SMTP_USER not set!'
test -z "$SMTP_PASS" && panic 'SMTP_PASS not set!'

test -z "$MAIL_BODY" && test -z "$MAIL_ATTACHMENT_DATA" \
	&& panic 'No message content!'

SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"
SMTP_PORT=${SMTP_PORT:-465}

MAIL_FROM=${MAIL_FROM:-$SMTP_USER}
MAIL_TO=${MAIL_TO:-$MAIL_FROM}

FROM_ADDRESS="$(extract_address "$MAIL_FROM")"
TO_ADDRESS="$(extract_address "$MAIL_TO")"

DISPLAY_FROM="$(rfc_2047 "$MAIL_FROM")"
DISPLAY_TO="$(rfc_2047 "$MAIL_TO")"
DISPLAY_SUBJECT="$(rfc_2047 "$MAIL_SUBJECT")"

TMP_FILE="/tmp/email.$(date +%Y%m%d%H%M%S).eml"
trap 'rm -f "$TMP_FILE"' EXIT INT TERM

MULTIPART_BOUNDARY='FZXVWxacmNHRlJNbU01VUZGdlBRbz0K'

DATE_HEADER="$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S +0000')"

cat << EOF > ${TMP_FILE}
From: ${DISPLAY_FROM} <${FROM_ADDRESS}>
To: ${DISPLAY_TO} <${TO_ADDRESS}>
Subject: ${DISPLAY_SUBJECT}
Date: ${DATE_HEADER}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="${MULTIPART_BOUNDARY}"

--${MULTIPART_BOUNDARY}
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: base64

$(to_base64 "$MAIL_BODY")

EOF

test -n "$MAIL_ATTACHMENT_NAME" && {
	cat << EOF >> ${TMP_FILE}
--${MULTIPART_BOUNDARY}
Content-Type: ${MAIL_ATTACHMENT_MIME_TYPE}; name="${MAIL_ATTACHMENT_NAME}"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="${MAIL_ATTACHMENT_NAME}"

${MAIL_ATTACHMENT_DATA}

EOF
}

printf '%s' "--${MULTIPART_BOUNDARY}--" >> "${TMP_FILE}"

test -n "$DEBUG" && {
	cat "$TMP_FILE"
}

if test "$SMTP_PORT" -eq 465; then
	curl -sS --ssl-reqd \
			 --url "smtps://${SMTP_HOST}:${SMTP_PORT}" \
			 --user "${SMTP_USER}:${SMTP_PASS}" \
			 --mail-from "$FROM_ADDRESS" \
			 --mail-rcpt "$TO_ADDRESS" \
			 --upload-file "$TMP_FILE" \
	&& print_sent
else
	curl -sS --ssl \
			 --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
			 --user "${SMTP_USER}:${SMTP_PASS}" \
			 --mail-from "$FROM_ADDRESS" \
			 --mail-rcpt "$TO_ADDRESS" \
			 --upload-file "$TMP_FILE" \
	&& print_sent
fi
