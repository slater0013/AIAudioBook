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

### Télécharger le DMG (recommandé)

1. Allez dans la section [**Releases**](https://github.com/slater0013/AIAudioBook/releases) du dépôt
2. Téléchargez `AIudioBook-vX.X.X.dmg`
3. Ouvrez le DMG, faites glisser **AIudioBook** vers le dossier **Applications**
4. Au premier lancement : clic droit → **Ouvrir** (nécessaire car l'app n'est pas encore signée Apple)

### Depuis les sources

```bash
git clone https://github.com/slater0013/AIAudioBook.git
cd AIAudioBook
open AIudioBook.xcodeproj
```

Puis **Product › Run** dans Xcode (⌘R).

## TTS haute qualité — Kokoro FastAPI (optionnel)

Par défaut, AIudioBook utilise les voix natives macOS (AVSpeechSynthesizer). Pour une voix nettement plus naturelle, vous pouvez connecter le serveur **Kokoro FastAPI** qui tourne localement sur votre machine.

### Prérequis

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé et lancé

### Lancement du serveur Kokoro

**CPU (compatible tous Mac) :**
```bash
docker run -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:v0.2.1
```

**GPU Apple Silicon (M1/M2/M3/M4, plus rapide) :**
```bash
docker run -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-mps:v0.2.1
```

Le serveur est prêt quand le terminal affiche `Uvicorn running on http://0.0.0.0:8880`.

### Alternative : installation pip

```bash
pip install kokoro-fastapi
kokoro-fastapi serve
```

> L'intégration Kokoro dans AIudioBook est en cours de développement (voir feuille de route). Une fois disponible, il suffira de renseigner l'adresse `http://localhost:8880` dans les préférences TTS de l'application.

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

- [ ] Intégration Kokoro FastAPI (voix TTS haute qualité via serveur local)
- [ ] Règles de substitution TTS personnalisables (abréviations bibliques, médicales…)
- [ ] RAG complet (NLEmbedding + recherche vectorielle) pour l'assistant IA
- [ ] Surlignage de texte permanent
- [ ] Pagination vraie (type livre papier)

## Licence

MIT — voir [LICENSE](LICENSE).
