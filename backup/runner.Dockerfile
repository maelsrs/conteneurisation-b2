FROM alpine:3.20

RUN apk add --no-cache restic openssh-client postgresql16-client bash curl

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh \
    && printf 'Host backup-server\n  User backup\n  StrictHostKeyChecking accept-new\n' > /root/.ssh/config

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh \
    && echo "*/5 * * * * /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
