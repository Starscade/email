One-liner email script.

###### INSTALLATION
```
curl -fLsSo ~/.local/bin/email https://email.angus.sh/install.sh
chmod +x ~/.local/bin/email
```

###### USAGE
```
export SMTP_HOST=smtp.example.com
export SMTP_PASS=Jelszo
export SMTP_USER=foo@example.com

email --subject 'Ahoy!' --body 'Lorem ipsum, etc.'
```
