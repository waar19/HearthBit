# Validation du radar et de la mesure de distance

[English](radar-ranging-validation.en.md) ·
[Español](radar-ranging-validation.md) ·
[Deutsch](radar-ranging-validation.de.md) · **Français** ·
[简体中文](radar-ranging-validation.zh.md) ·
[日本語](radar-ranging-validation.ja.md)

## Portée et sécurité

- Le GPS guide à longue distance.
- Le RSSI BLE indique proximité et tendance, pas une direction physique.
- Le balayage BLE expérimental expire après 90 secondes ou 15 m.
- Android Ranging utilise Channel Sounding, Wi-Fi NAN RTT ou RSSI BLE sur
  Android 16+, selon le matériel.
- Le sonar acoustique mesure de courtes distances en trois cycles de type
  BeepBeep.

Le sonar fonctionne mieux entre 1 et 25 m, sans obstacle. Ne pas l’utiliser
près de l’oreille ; les enfants et animaux peuvent entendre les hautes
fréquences. Aucune mesure ne remplace le jugement des secours.

## Interface

1. Ouvrir le radar sur un écran étroit.
2. Dégrader l’étalonnage près d’un objet métallique.
3. Vérifier qu’une seule bannière apparaît et que le cercle ne bouge pas.
4. Faire un mouvement en huit et vérifier la disparition sans saut de page.
5. Lancer un balayage ; le guide doit se superposer au cercle.
6. Après 90 secondes ou 15 m, un nouveau balayage doit être demandé.

## Android Ranging

Avec deux appareils Android 16+ et l’autorisation `RANGING` :

1. Activer le maillage et le consentement radar sur la cible.
2. Ouvrir le radar sur l’autre téléphone et lancer la mesure radio.
3. Vérifier la distance mesurée et la marge d’erreur.
4. Répéter à 1, 3, 5 et 10 m, en visibilité directe puis avec un mur.

## Sonar Android–iPhone

1. Garder l’application ouverte et accorder radar et microphone.
2. Déconnecter les casques Bluetooth ; dégager haut-parleurs et microphones.
3. Placer les appareils à 1–3 m et lancer la mesure acoustique.
4. Rester immobile pendant trois cycles et comparer avec un mètre.
5. Répéter à 5, 10 et 20 m, puis avec du bruit.

Si deux chirps ne sont pas détectés par cycle, HearthBit doit rejeter le
résultat.

## Notification Android persistante

Activer le maillage, balayer la notification sous Android 14+ et vérifier
qu’elle réapparaît. Après l’arrêt du maillage, elle doit disparaître
définitivement.
