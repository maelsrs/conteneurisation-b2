# Serveur de sauvegarde : simple serveur SSH/SFTP qui héberge le dépôt restic
FROM alpine:3.20

RUN apk add --no-cache openssh \
    && ssh-keygen -A \
    && adduser -D backup \
    # Déverrouille le compte pour l'auth par clé uniquement (pas de mot de passe)
    && sed -i 's/^backup:!/backup:*/' /etc/shadow \
    && mkdir -p /backups /home/backup/.ssh \
    && chown backup:backup /backups /home/backup/.ssh \
    && chmod 700 /home/backup/.ssh \
    # Auth par clé uniquement (étape 3 : accès restreint aux utilisateurs autorisés)
    && echo "PasswordAuthentication no" >> /etc/ssh/sshd_config \
    && echo "PermitRootLogin no" >> /etc/ssh/sshd_config \
    && echo "AllowUsers backup" >> /etc/ssh/sshd_config

COPY keys/id_ed25519.pub /home/backup/.ssh/authorized_keys
RUN chown backup:backup /home/backup/.ssh/authorized_keys \
    && chmod 600 /home/backup/.ssh/authorized_keys

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
