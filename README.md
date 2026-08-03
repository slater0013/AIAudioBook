# AIudioBook

Lecteur EPUB natif pour macOS avec lecture à voix haute et assistance IA, entièrement local et sans abonnement.

## Fonctionnalités

### Bibliothèque
- Importation de fichiers EPUB par glisser-déposer ou via le sélecteur de fichiers
- Affichage des couvertures, titres et auteurs
- Mémorisation automatique de la dernière position de lecture

### Lecteur
- Rendu natif des chapitres (NSTextView) — pas de WebView, compatible App Sandbox
- Table des matières interactive avec navigation par chapitre
- Mode défilement ou mode pages
- Thèmes clair, sépia et sombre
- Taille de police ajustable (12–28 pt)
- Recherche intégrée (Cmd+F)
- **Signets** : ajout/suppression en un clic, liste avec navigation directe

### Lecture à voix haute (TTS)
- Moteur natif macOS (AVSpeechSynthesizer)
- Surlignage mot à mot en temps réel (mode karaoké)
- Reprise depuis la position du curseur
- Vitesse, voix et langue configurables
- Prétraitement intelligent : chiffres romains, abréviations, notes de bas de page éliminées

### Assistant IA
- Panneau de questions/réponses sur le contenu du livre
- Indexation locale du texte (FoundationModels)
- Contexte extrait automatiquement du chapitre en cours

## Configuration requise

- macOS 26 ou ultérieur
- Xcode 26 (pour compiler depuis les sources)

## Installation

### Depuis les sources

```bash
git clone https://github.com/<votre-compte>/AIudioBook.git
cd AIudioBook
open AIudioBook.xcodeproj
```

Puis **Product › Run** dans Xcode (⌘R).

## Architecture

```
AIudioBook/                  ← cible principale macOS
Packages/AIudioBookCore/     ← Swift Package local (modules réutilisables)
  Sources/
    EPUBKit/                 ← parseur EPUB 2 & 3 (OPF, NCX, nav)
    LibraryFeature/          ← bibliothèque, modèle Book (SwiftData), signets
    ReaderFeature/           ← lecteur, TTS, panneau IA
ZIPFoundation/               ← dépendance locale (décompression EPUB)
```

## Feuille de route

- [ ] Règles de substitution TTS personnalisables (abréviations bibliques, médicales…)
- [ ] RAG complet (NLEmbedding + recherche vectorielle) pour l'assistant IA
- [ ] Surlignage de texte permanent
- [ ] Pagination vraie (type livre papier)

## Licence

MIT — voir [LICENSE](LICENSE).
