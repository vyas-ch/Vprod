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

De meegeleverde configuratie biedt eerst HTTP. Zet de A-records van `vprod.nl` en `vproduction.nl` op het juiste VPS-adres; controleer ook de www-records en bestaande AAAA-records. Vraag daarna certificaten aan voor de bevestigde namen, activeer HTTPS en stuur `vproduction.nl` door naar `https://vprod.nl`. Beweer pas dat de site live is op HTTPS als de publieke controles slagen.

De projectplanner verstuurt zelf geen gegevens. Het publieke contactadres en de definitieve Higgsfield-video moeten nog worden ingevuld. Publiceer geen .env, sleutels, persoonlijke backups of lokale bronafbeeldingen.
