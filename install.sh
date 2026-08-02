#!/bin/sh

test $(basename "$0") = 'install.sh' && {
	INSTALL_DIR=~/.local/bin
	test -n "$1" && test -d "$1" \
		&& INSTALL_DIR="$1"
	INSTALL_PATH="${INSTALL_DIR}/smail"
	mkdir -pv "$INSTALL_DIR" \
	&& cp -iv "$0" "$INSTALL_PATH" \
	&& chmod -v 0755 "$INSTALL_PATH"
	exit
}

extract_address() {
	echo "$1" | sed 's/.*<\(.*\)>/\1/'
}

panic() {
	printf "\n  \033[1;31mERR\033[0m: ${1}\n\n"
	exit 1
}

print_ok() {
	printf "\n  \033[1;32mOK\033[0m  ${1}\n\n"
}

rfc_2047() {
	printf '=?UTF-8?Q?'
	printf '%s' "$1" | od -An -v -tx1 | tr ' \n' '=' | tr '[:lower:]' '[:upper:]'
	printf '?='
}

to_base64() {
	CR="$(printf '\r')"

	printf '%s' "$1" \
	| base64 \
	| tr -d '\n' \
	| fold -w 76 \
	| awk -v cr="$CR" '{print $0 cr}'
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
				'https://smail.angus.sh/install.sh' \
				&& print_ok "\033[1m$($(command -v "$0") --version)\033[0m" \
				|| panic 'Upgrade failed!'
			exit
			;;
		--env)
			shift
			DOTENV_FILE="$1"
			test -s "$DOTENV_FILE" && {
				set -a
				. "$DOTENV_FILE"
				set +a
			} || panic "Failed to load \"${DOTENV_FILE}\"."
			;;
		--from)
			shift
			MAIL_FROM="$1"
			;;
		--to)
			shift
			MAIL_TO="$1"
			;;
		--subject)
			shift
			MAIL_SUBJECT="$1"
			;;
		--body)
			shift
			if test -s "$1"; then
				MAIL_BODY="$(cat "$1")"
			else
				MAIL_BODY="$1"
			fi
			;;
		--attach)
			shift
			test -s "$1" || panic 'No file!'
			MAIL_ATTACHMENT_DATA=$(to_base64 "$(cat "$1")")
			MAIL_ATTACHMENT_MIME_TYPE=$(
				file -b --mime-type "$1" 2>/dev/null \
				|| echo "text/plain"
			)
			MAIL_ATTACHMENT_NAME="$1"
			;;
		*)
			panic "\033[1m${1}\033[0m is not a recognized argument."
			;;
	esac
	shift
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

TMP_FILE="/tmp/smail.$(date +%Y%m%d%H%M%S).eml"
MULTIPART_BOUNDARY='U01BSUxfQk9VTkRBUlkK'

DATE_HEADER="$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S +0000')"

cat << EOF > ${TMP_FILE}
From: ${MAIL_FROM}
To: ${MAIL_TO}
Subject: ${MAIL_SUBJECT}
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

curl -sS --ssl-reqd \
     --url "smtps://${SMTP_HOST}:${SMTP_PORT}" \
     --user "${SMTP_USER}:${SMTP_PASS}" \
     --mail-from "$FROM_ADDRESS" \
     --mail-rcpt "$TO_ADDRESS" \
     --upload-file "$TMP_FILE" \
&& printf "\n  \033[1;32mSENT\033[0m\n\n"

rm "$TMP_FILE"
