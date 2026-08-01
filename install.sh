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

get_date() {
	date -u +'%a, %d %b %Y %H:%M:%S +0000'
}

panic() {
	printf "\n  \033[1;31mERR\033[0m: ${1}\n\n"
	exit 1
}

test -z "$SMTP_USER" && panic 'SMTP_USER not set!'
test -z "$SMTP_PASS" && panic 'SMTP_PASS not set!'

SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"
SMTP_PORT=${SMTP_PORT:-465}

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
				|| print_err 'Upgrade failed!'
			exit
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
			MAIL_BODY="$1"
			;;
		*)
			panic "\033[1m${1}\033[0m is not a recognized argument."
			;;
	esac
	shift
done

test -z "$MAIL_BODY" && panic 'No message body!'

MAIL_FROM=${MAIL_FROM:-$SMTP_USER}
MAIL_TO=${MAIL_TO:-$SMTP_USER}
FROM_ADDRESS="$(extract_address "$MAIL_FROM")"
TO_ADDRESS="$(extract_address "$MAIL_TO")"

echo "HOST: ${SMTP_HOST}"
echo "USER: ${SMTP_USER}"
echo "FROM: ${MAIL_FROM}"
echo "TO: ${MAIL_TO}"

TMP_FILE=$(mktemp)

cat << EOF > ${TMP_FILE}
From: ${MAIL_FROM:-$SMTP_USER}
To: ${MAIL_TO:-$SMTP_USER}
Subject: ${MAIL_SUBJECT}
Date: $(date -u +'%a, %d %b %Y %H:%M:%S +0000')
MIME-Version: 1.0
Content-Type: ${MIME_TYPE:-text/html}; charset=UTF-8

${MAIL_BODY}

EOF

curl -sS "smtps://${SMTP_HOST}:${SMTP_PORT}" \
     -u "${SMTP_USER}:${SMTP_PASS}" \
     --ssl-reqd \
     --mail-from "$SMTP_USER" \
     --mail-rcpt "$TO_ADDRESS" \
     --upload-file "$TMP_FILE"

rm -v "$TMP_FILE"
