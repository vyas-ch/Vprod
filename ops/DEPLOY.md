# V Production op de VPS

De eerste inspectie van de VPS vond geen webserver of bestaande website. De publieke site is volledig statisch en wordt daarom rechtstreeks door Nginx bediend. Node.js is alleen nodig voor de lokale preview en lokale tests.

## Eerste installatie

Gebruik uitsluitend een gepushte, geteste Git-commit. Maak met `git archive` een tar van `public` en `ops`; bereken de SHA-256 en plaats het pakket met `setup-vps.sh` in de persoonlijke stagingmap op de server.

Voer de voorbereide installatie via een interactieve SSH-terminal uit:

```sh
sudo /bin/bash setup-vps.sh release.tar SHA256 GIT_COMMIT
```

De installatie verifieert het pakket, bewaart de vorige V Production-configuratie onder `/var/backups/vprod`, plaatst een onveranderlijke release onder `/srv/vprod/releases`, installeert Nginx vanuit Ubuntu en wisselt de `current`-symlink. Alleen de V Production-siteconfiguratie wordt gewijzigd. Configuratievalidatie en lokale HTTP-controles zijn verplicht. Bij een fout wordt de vorige configuratie teruggezet; een nieuw gestarte Nginx wordt bij mislukte activering gestopt.

`/srv/vprod/deploy-status.txt` wordt pas geschreven als alle controles slagen. Een geslaagde lokale installatie bewijst nog geen bereikbaarheid via internet; controleer daarna het server-IP, beide Host-namen, assets, beveiligingsheaders en redirects vanaf een andere machine.

## Domeinen en HTTPS

De eerste configuratie biedt HTTP. Zet de A-records van `vprod.nl` en `vproduction.nl` op het juiste VPS-adres; controleer ook de www-records en bestaande AAAA-records. Op 30 september 2026 zijn beide A-records naar de VPS gezet en de oude AAAA-records verwijderd. De gebruiker bevestigde dat er nog geen e-mail in gebruik is. De overige DNS-records en DNSSEC zijn behouden.

De eenmalige HTTPS-installatie is op 30 september 2026 geslaagd, inclusief de proefvernieuwing. Normale website-updates gaan voortaan via GitHub. Alleen voor expliciete wijzigingen aan de serverconfiguratie is de beheerroute hieronder nodig; stop daarvoor eerst de deploytimer:

```sh
sudo /bin/bash deploy-vps.sh release.tar SHA256 GIT_COMMIT VORIGE_GIT_COMMIT
```

Dit script stopt wanneer een andere release actief is dan verwacht, maakt een backup, controleert DNS en het ACME-pad en vraagt één Let's Encrypt-certificaat aan voor beide domeinen met en zonder www. Er wordt geen persoonlijk e-mailadres aan het certificaataccount gekoppeld. De hoofdpagina staat op `https://vprod.nl`; de overige namen en HTTP verwijzen daarheen. De automatische vernieuwing gebruikt Certbot, een timer en een Nginx-herlaadactie. Een proefvernieuwing en HTTPS-controles moeten slagen voordat de deploystatus wordt bijgewerkt. Bij een fout worden de vorige siteconfiguratie, release en status teruggezet; geïnstalleerde pakketten en verkregen certificaten blijven behouden.

Gebruik `setup-vps.sh` alleen voor de eerste HTTP-installatie; het weigert bestaande certificaten te overschrijven. Controleer na iedere deploy ook publiek HTTPS, certificaatnamen, redirects, de videostream en de hashes van alle publieke bestanden. Lokale controles bewijzen nog geen publieke bereikbaarheid.

De projectplanner verstuurt zelf geen gegevens. Het publieke contactadres moet nog worden ingevuld. De gecontroleerde Higgsfield-montage is opgenomen in de release. Publiceer geen .env, sleutels, persoonlijke backups of lokale bronafbeeldingen.

## Codex → GitHub → VPS

Na de eerste geslaagde HTTPS-installatie voert de beheerder eenmaal `sudo bash /srv/vprod/releases/GIT_COMMIT/ops/install-auto-deploy.sh GIT_COMMIT` uit. Dit installeert de timer `vprod-deploy.timer` en een account zonder login of sudo. De deploycode blijft root-eigendom. Het account kan uitsluitend de websitebestanden, actieve releaselink en eigen Git-cache wijzigen; systemd beperkt de schrijfpaden tot deze directories.

De timer leest de openbare repository iedere minuut. Hij wacht op een geslaagde push-workflow `website.yml` voor exact de laatste `main`-commit. Daarna haalt hij die commit op, publiceert uitsluitend toegestane bestanden onder `public`, wisselt de releaselink en vergelijkt de HTTPS-respons met de release. Bij mislukte controles wordt de vorige link hersteld. Repositoryscripts worden nooit door deze service uitgevoerd. Certificaten, Nginx-configuratie, SSH en serverrechten worden niet automatisch uit de repository gewijzigd.

De GitHub-workflow heeft alleen leesrechten. Er zijn geen deploysleutels of repository secrets nodig. Dit werkt zolang `vyas-ch/Vprod` openbaar is. Bij een privémigratie stopt ophalen veilig en blijft de huidige website draaien; configureer dan eerst een passende leesverbinding.

Controle: `systemctl status vprod-deploy.timer`, `journalctl -u vprod-deploy.service`, `/srv/vprod/deploy-status.txt` en `/srv/vprod/deployments/`. Voer tijdens beheer aan serverconfiguratie eerst `systemctl stop vprod-deploy.timer` uit en hervat na de controles. Oudere releases blijven beschikbaar. Een geslaagde GitHub-check bewijst pas een deploy wanneer de VPS-status en publieke HTTPS-controles overeenkomen.
