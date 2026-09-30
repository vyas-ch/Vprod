# V Production

Nederlandse website op basis van het gekozen filmische concept. Bevat het bestaande logo in drie horizontale blokken, IT/video/audio-diensten, een filter, mobiel menu en een projectplanner.

## Lokaal

Node.js 22 of hoger. Geen externe npm-pakketten nodig.

```sh
npm start
npm test
npm run check
```

Preview: http://127.0.0.1:4173. De Node-server luistert standaard alleen lokaal. De publieke site is volledig statisch; de VPS gebruikt hiervoor Nginx.

## Content en video

- Publieke contactgegevens staan in `public/site-config.js`. E-mailadres en telefoon zijn nog niet aangeleverd. De projectplanner maakt daarom nu een kopieerbaar concept. Er wordt niets automatisch verzonden.
- De Higgsfield-montage in `public/assets/vprod-montage.mp4` toont radio, podcast, film, IT en websites (15 seconden, 1920×1080, 24 fps, zonder geluid). De webversie is circa 4 MB. De video heeft een pauzeknop en laadt pas op verzoek bij een klein scherm, databesparing of verminderde beweging.
- De montage en sfeerbeelden zijn gegenereerd met Higgsfield en ImageGen. Ze stellen geen bestaand klantportfolio of eigen studio voor.
- Het logo is overgenomen uit de goedgekeurde SVG-assets in navy/cyaan.
- Hoofdadres: `https://vprod.nl`; `vproduction.nl` en beide www-adressen verwijzen hierheen.

## Publicatie

De website met video is sinds 30 september 2026 bereikbaar via HTTPS. Nginx bedient de statische bestanden op de VPS; Let's Encrypt verzorgt het certificaat voor beide domeinen en hun www-adressen. De automatische certificaatvernieuwing is met een proefvernieuwing gecontroleerd. Publieke contactgegevens moeten nog worden ingevuld. De repository bevat geen sleutels of omgevingsgeheimen. Alleen de map `public` wordt gepubliceerd. De serverstatus en publieke controles bepalen welke commit daadwerkelijk draait.

Normale updates verlopen via GitHub. Zie `ops/DEPLOY.md` voor de geïnstalleerde deployservice, controles en serverbeheer.

## Automatische updates

Codex zet wijzigingen in GitHub. De workflow `Website checks` controleert de code, videostreaming en veilige releasebestanden. De VPS controleert iedere minuut of de nieuwste commit op `main` deze controles heeft doorstaan. Alleen dan activeert hij de publieke bestanden, met controle en automatisch herstel bij een fout. Hiervoor zijn geen serverwachtwoord, SSH-privésleutel of GitHub-token op de VPS nodig. De eenmalige installatie van Nginx, HTTPS en de deployservice vereist wel beheerdersrechten. Zie `ops/DEPLOY.md` voor de installatie en statuscontrole.
