# Transparence et confidentialité

HearthBit publie son code afin que l’identité, le chiffrement, la localisation,
le fonctionnement en arrière-plan et l’interopérabilité puissent être audités.
Le projet est source-available, mais n’est pas open source approuvé par l’OSI.

## Données et réseau

Le maillage local ne nécessite pas de compte central. L’identité et les clés
sont créées sur l’appareil ; messages, transferts et envois en attente peuvent
être stockés localement. L’application principale n’exige pas d’analytique.
Cependant, les cartes en ligne, les passerelles MQTT/Matrix/LAN facultatives,
les liens externes et Google Play Services peuvent transmettre des données à
d’autres opérateurs.

Les signaux BLE sont observables à proximité. Les messages publics ne sont pas
confidentiels. Les messages privés utilisent Noise XX, mais la présence radio,
les horaires et certains métadonnées de routage peuvent rester visibles.

## Position et distance

GPS, RSSI BLE, Android Ranging et sonar acoustique ont des sources d’erreur
différentes. Un balayage BLE expire après 90 secondes ou 15 m de déplacement.
Le sonar traite de courts enregistrements PCM en mémoire et émet des sons à
haute fréquence que des personnes, animaux ou microphones voisins peuvent
détecter. Les mesures ne sont pas certifiées.

Le radar, la position et la mesure acoustique nécessitent un consentement
temporaire. Android affiche une notification persistante lorsque le maillage
est actif ; iOS contrôle lui-même l’activité BLE en arrière-plan.

## Limites

HearthBit ne garantit ni la livraison, ni l’anonymat, ni la résistance au
brouillage, ni l’identité réelle derrière un pseudonyme, ni la protection d’un
appareil compromis. L’application ne remplace pas les services d’urgence
officiels. Un signalement de sécurité ne doit pas publier d’identifiants, de
positions, d’enregistrements ou de messages d’urgence réels.

## Licence

Le code original HearthBit est soumis à PolyForm Noncommercial 1.0.0 ; un
accord distinct est nécessaire pour l’usage commercial. Les versions déjà
publiées sous MIT restent sous MIT. Les tiers et sous-modules conservent leurs
licences. Voir [`LICENSE`](../LICENSE), [`NOTICE.md`](../NOTICE.md) et
[`COMMERCIAL-LICENSE.md`](../COMMERCIAL-LICENSE.md).
