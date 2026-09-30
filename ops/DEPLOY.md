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

Gebruik voor de video, HTTPS en volgende releases:

```sh
sudo /bin/bash deploy-vps.sh release.tar SHA256 GIT_COMMIT VORIGE_GIT_COMMIT
```

Dit script stopt wanneer een andere release actief is dan verwacht, maakt een backup, controleert DNS en het ACME-pad en vraagt één Let's Encrypt-certificaat aan voor beide domeinen met en zonder www. Er wordt geen persoonlijk e-mailadres aan het certificaataccount gekoppeld. De hoofdpagina staat op `https://vprod.nl`; de overige namen en HTTP verwijzen daarheen. De automatische vernieuwing gebruikt Certbot, een timer en een Nginx-herlaadactie. Een proefvernieuwing en HTTPS-controles moeten slagen voordat de deploystatus wordt bijgewerkt. Bij een fout worden de vorige siteconfiguratie, release en status teruggezet; geïnstalleerde pakketten en verkregen certificaten blijven behouden.

Gebruik `setup-vps.sh` alleen voor de eerste HTTP-installatie; het weigert bestaande certificaten te overschrijven. Controleer na iedere deploy ook publiek HTTPS, certificaatnamen, redirects, de videostream en de hashes van alle publieke bestanden. Lokale controles bewijzen nog geen publieke bereikbaarheid.

De projectplanner verstuurt zelf geen gegevens. Het publieke contactadres moet nog worden ingevuld. De gecontroleerde Higgsfield-montage is opgenomen in de release. Publiceer geen .env, sleutels, persoonlijke backups of lokale bronafbeeldingen.
