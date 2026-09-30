# V Production

Nederlandse website op basis van het gekozen filmische concept. Bevat het bestaande logo in drie horizontale blokken, IT/video/audio-diensten, een filter, mobiel menu en een projectplanner.

## Lokaal

Node.js 22 of hoger. Geen externe npm-pakketten nodig.

```sh
npm start
npm test
npm run check
```

Preview: http://127.0.0.1:4173. De server luistert standaard alleen lokaal; gebruik een TLS reverse proxy voor productie.

## Content en video

- Publieke contactgegevens staan in `public/site-config.js`. E-mailadres en telefoon zijn nog niet aangeleverd. De projectplanner maakt daarom nu een kopieerbaar concept. Er wordt niets automatisch verzonden.
- `heroVideo` blijft leeg tot de Higgsfield-montage is gerenderd en gecontroleerd. Voeg het MP4-bestand toe onder `public/assets` en zet het lokale pad in de configuratie. De video speelt gedempt, heeft een pauzeknop en laadt pas op verzoek bij een klein scherm, databesparing of verminderde beweging.
- De geplande montage toont radio, podcast, film, IT en websites. De huidige sfeerbeelden zijn met ImageGen gegenereerd; ze stellen geen bestaand klantportfolio of eigen studio voor.
- Het logo is overgenomen uit de goedgekeurde SVG-assets in navy/cyaan.
- Primaire domeinkeuze: `vprod.nl`; `vproduction.nl` kan erheen doorverwijzen.

## Publicatie

Nog niet live. Controleer vóór publicatie de contactgegevens, definitieve diensten, domeinverwijzingen en servertoegang. De repository bevat geen sleutels of omgevingsgeheimen. De statische server publiceert uitsluitend de map `public`.

Zie `ops/DEPLOY.md` voor de voorbereide serveraanpak. Deploy alleen een geteste commit. Gebruik een aparte releasefolder, bewaar de vorige release en wijzig alleen de V Production-service.
