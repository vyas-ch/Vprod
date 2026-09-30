# V Production deploy

Status: voorbereid, nog niet uitgevoerd. De bestaande VPS-configuratie moet eerst worden geïnspecteerd. Pas poorten, gebruikers en paden zo nodig aan zonder andere sites te verstoren.

1. Controleer SSH-toegang, bestaande websites, reverse proxy, poorten, schijfruimte en Node-versie.
2. Bewaar de bestaande V Production-configuratie en vorige release in een backupfolder met datum. Bij een eerste publicatie: registreer dat er nog geen V Production-release was.
3. Plaats uitsluitend de geteste Git-commit in een nieuwe map onder `/srv/vprod/releases/<commit>`. Upload geen lokale output, sleutels, .env of backups.
4. Stel een eigen servicegebruiker en een ongebruikte lokale poort in. Voorbeeld: `HOST=127.0.0.1 PORT=4173 node server.mjs`.
5. Controleer via localhost: homepage, assets, privacy en MP4 range requests. Wissel daarna de `current`-symlink naar de nieuwe release en herstart uitsluitend de V Production-service.
6. Voeg een eigen reverse-proxy-site toe in de bestaande serverconfiguratie. Valideer de volledige configuratie vóór reload. Gebruik TLS, stuur `vproduction.nl` naar `vprod.nl`, en behoud bestaande sites.
7. Pas DNS pas aan na verificatie van de juiste VPS. Controleer daarna publiek beide domeinen, HTTPS, redirect, contactroute en video.
8. Bij een fout: herstel de vorige symlink/configuratie, herstart uitsluitend V Production en controleer opnieuw. Bewaar het manifest met commit, bestands-hashes en uitkomst buiten de publieke webroot.

Er zijn bewust geen ongeteste servercommando's automatisch uitgevoerd.
