# info@vprod.nl op de bestaande VPS

De voorbereiding gebruikt Ubuntu 26.04, Postfix 3.10 en Dovecot 2.4 met één virtuele mailbox. Ontvangst en IMAP blijven op de eigen VPS. Uitgaande berichten gebruiken de gratis, geauthenticeerde TransIP VPS-mailservice. Er wordt geen abonnement besteld en geen VPS-upgrade uitgevoerd.

Dit document beschrijft de beoogde installatie. De mailbox is pas gereed nadat de beheerinstallatie én de publieke controles zijn geslaagd. De websitecontactconfiguratie blijft tot dat moment ongewijzigd.

## Installatie

`setup-mail.sh` wordt met sudo uitgevoerd vanuit een gecontroleerd pakket van deze ops-bestanden. Het argument is de VPS-mailservice-gebruikersnaam. Het bestaande SMTP-wachtwoord wordt onzichtbaar op de VPS gevraagd; het mailboxwachtwoord wordt daar willekeurig gegenereerd. Geen van beide hoort in Git, een chatbericht of een installatielog.

De installer verifieert het lokale IP-adres en de vastgelegde publieke SSH-serveridentiteit. De TransIP-weergavenaam `vyas-vps2` verschilt van de Ubuntu-hostname `cloud.example.com`; die namen zijn daarom geen identiteitscontrole. De installer weigert een andere VPS/Ubuntu-versie, bestaande mailpakketten of een al voltooide mailinstallatie. Hij bewaart de vorige configuratie in een map met modus 0700 onder `/var/backups/vprod-mail`, pauzeert de website-deploytimer en voegt 2 GiB swap toe als er geen swap aanwezig is. De bestaande Nginx-site blijft behouden. Alleen een aparte HTTP-vhost voor het mailcertificaat wordt toegevoegd. Maildiensten blijven tijdens pakketinstallatie gemaskeerd totdat hun configuraties zijn gecontroleerd.

De actieve processen zijn Postfix, Dovecot en één Rspamd-scanner; Redis, Docker en ClamAV worden niet geïnstalleerd. Geheugenlimieten beperken de gevolgen van een scanner- of IMAP-probleem. Bij scanneruitval wordt inkomende mail tijdelijk geweigerd zodat de verzendende mailserver opnieuw kan proberen. Deze instellingen bewijzen niet dat 1 GB voor ieder verkeerspatroon voldoende is. De eerste gezondheidscontrole moet slagen.

Bij een mislukking stopt de installer maildiensten, verwijdert hij zijn eigen Nginx-vhost en hervat hij de vooraf actieve deploytimer. Pakketten, swap, verkregen certificaten en diagnostische configuraties blijven bestaan. Herhaal de eerste-installatiescript niet blind: inspecteer de fout en herstel gericht vanuit de backup.

## DNS en clients

- A `mail.vprod.nl`: `37.97.129.7`.
- MX voor `vprod.nl`: `10 mail.vprod.nl.` zodra publieke ontvangst werkt.
- SPF: `v=spf1 include:_spf.transip.email ~all`.
- DKIM en `x-transip-mail-auth`: bestaande, door TransIP geleverde waarden; verifieer echte DKIM-signing in ontvangen uitgaande mail.
- DMARC blijft aanvankelijk `p=none` tot SPF/DKIM-alignment is gecontroleerd.
- IMAP: `mail.vprod.nl`, poort 993, SSL/TLS.
- SMTP: `mail.vprod.nl`, poort 587, STARTTLS en verplichte authenticatie.
- Gebruikersnaam: `info@vprod.nl` (volledig adres).

Alleen info heeft een mailbox. Het vereiste postmaster-adres en lokale beheerdersmeldingen komen in dezelfde inbox. Andere virtuele ontvangers worden geweigerd. POP3 en onversleutelde IMAP zijn niet geopend. Port25 biedt opportunistische STARTTLS voor andere mailservers; clientauthenticatie is daar uitgeschakeld.

De clientinstellingen met wachtwoord staan na installatie privé onder `/home/vyas/.config/vprod-mail/client.json` (0600), en worden door het persoonlijke afrondscript uitsluitend naar de eigen Mac gekopieerd buiten de repository. Toon de inhoud niet in tooloutput.

## Controle en beheer

Lokale acceptatie controleert TLS-certificaten, SMTP-authenticatie, afzenderbeperking, interne LMTP-bezorging en IMAP. De Rspamd-configuratie is tegen exact het Ubuntu-pakket gevalideerd; de actieve scanner en de externe mailroute vereisen aanvullende controles. De certificaatvernieuwing heeft een deployhook voor beide maildiensten en wordt met een dry-run getest.

Publieke acceptatie vereist bereikbaarheid op25/587/993, afwijzing van een externe ongeautoriseerde relaypoging vóór DATA, ontvangst in info via IMAP en uitgaande bezorging met passende SPF/DKIM/DMARC in een geautoriseerde externe mailbox. Een succesvolle lokale self-mail of lege wachtrij bewijst geen bezorging bij Gmail/Outlook.

`mail-health.py` geeft JSON zonder mailinhoud, credentials of wachtrijadressen. Een servertimer schrijft elke vijf minuten `/var/lib/vprod-mail/health.json`. Op verzoek van de gebruiker is er geen periodieke controle door Codex. Inspecteer het rapport wanneer de gebruiker om een controle vraagt; maak hiervoor geen automatische Codex-taak aan.

Dagelijkse mailboxbackups en een afzonderlijke configuratiebackup blijven beveiligd op de VPS. De mailbackup wordt als eigen gebruikersbestand beschikbaar gemaakt voor een kopie naar de eigen Mac; de configuratiebackup blijft root-only. Behoud zeven versies en controleer de SHA256. Een leesbaar archief is nog geen volledige hersteltest; voer die apart uit in een geïsoleerde herstelmap.

Voor onderhoud: `systemctl status postfix dovecot rspamd`, `systemctl status vprod-mail-health.timer`, en de JSON-rapporten. Gebruik geen volledige mailboxinhoud of credentials in publieke issues of logs. Werk publieke contactgegevens pas bij als de mailbox aantoonbaar werkt.
