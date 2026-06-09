# Launch Night — Thunderstorm Channel #1

> **Cible go-live :** 2026-06-10, 02:00 (heure Tariq)
> **Niche verrouillée :** Thunderstorm + heavy rain ambient, faceless, 24/7
> **Mode lancement :** public direct (décision Tariq — pas de unlisted en preview)
> **Contrainte dure :** ZÉRO copyright strike. Tout asset doit passer le Content ID check.

---

## Statut prep (live)

| Chantier | Statut | Bloqueur |
|----------|--------|----------|
| Sourcing assets (vidéo + audio) | ✅ shortlist faite | Tariq doit télécharger les fichiers sur la tour |
| Pipeline ffmpeg + systemd | ✅ scripts prêts | Aucun |
| Healthcheck Telegram | ✅ scripts prêts | Telegram bot token + chat_id + YouTube API key + channel ID |
| SEO metadata (titre/desc/tags/thumb) | ✅ rédigés | Thumbnail à produire (3 concepts décrits) |
| Stream key YouTube | ⏳ | Tariq doit la récupérer côté YouTube Studio à 2h |
| Content ID dry-run | ⏳ | Doit être fait AVANT le go-live (upload 30s unlisted) |

---

## ⚠️ Arbitrage critique à valider avant 2h

L'agent SEO recommande **NE PAS redémarrer le stream dans les 14 premiers jours** (le compteur d'ancienneté du flux est un signal algo majeur pour la chaîne neuve).

L'agent healthcheck propose **auto-restart sur panne** (sinon stream down = chaîne morte).

**Conflit réel.** Position d'Atlas :

- Auto-restart doit rester actif — sans lui, une coupure réseau de 30 secondes tue 24h de watch time avant que Tariq se réveille.
- MAIS : ajouter une couche "soft recover" qui tente d'abord de relancer ffmpeg **sans toucher au broadcast YouTube** (le stream RTMP reconnecte sur le même ingest, YouTube traite ça comme une reprise après glitch et garde la même live URL).
- Ne redémarrer le broadcast YouTube côté API que si la reconnexion RTMP échoue 3x d'affilée.

→ **À implémenter dans la v2 du healthcheck** si Tariq valide. Pour le go-live de 2h, on garde l'auto-restart simple — c'est mieux que zéro résilience.

---

## Runbook 2h du mat

### Avant 02:00 (Tariq, sur la tour Windows)

1. **Télécharger les assets shortlistés** (voir `assets/thunderstorm-assets.md`) dans `C:\Users\atlas\youtube-stream\assets\` :
   - Vidéo primaire : Pexels 9278554 (Kmeel.com — thunderstorms at night)
   - Vidéo backup : Pixabay 28067
   - Audio primaire : Pixabay 48572 (auralspectrawizard)
   - Audio backup : Pixabay 19565 (chrscrwfrd18, origine Freesound = plus safe)

2. **Content ID dry-run** (OBLIGATOIRE) :
   - Mux un échantillon de 30s vidéo+audio avec ffmpeg
   - Upload sur YouTube Studio en **unlisted**, monétisation ON
   - Attendre 10-15 min
   - Vérifier l'onglet "Droits d'auteur" → si zéro match, GO. Si match, swap pour le backup.

3. **Récupérer la stream key** :
   - YouTube Studio → Live → Stream → copier la stream key
   - **JAMAIS** la coller dans le repo. Uniquement dans `/etc/thunderstorm-stream.env` côté tower.

4. **Installer le pipeline** (suivre `pipeline/README-setup.md`).

### À 02:00 — Go-live

```bash
# Sur la tour, dans WSL2
sudo systemctl enable --now thunderstorm-stream.service
sudo systemctl enable --now thunderstorm-healthcheck.timer

# Vérifier
systemctl status thunderstorm-stream.service
journalctl -u thunderstorm-stream.service -f
```

### Côté YouTube Studio (Tariq)

1. Le broadcast doit déjà être créé en mode "Public" avec :
   - Titre, description, tags depuis `seo/thunderstorm-metadata.md`
   - Thumbnail uploadée (3 concepts décrits, à produire en avance)
   - Catégorie : "People & Blogs" ou "Entertainment" (PAS "Music" — éviter ContentID musical aggressif)
   - Live chat : ON
   - Monétisation : ON (si éligible)
2. Cliquer "Go Live" dès que ffmpeg envoie le flux.
3. Épingler le commentaire de bienvenue (template dans `seo/thunderstorm-metadata.md`).

### Après le go-live

- Atlas envoie un ping Telegram quand le healthcheck confirme le stream live.
- Daily digest tous les jours à 09:00 UTC.
- **Ne PAS toucher le stream les 14 premiers jours** sauf alerte healthcheck critique.

---

## Ce qui manque encore (à produire avant 2h)

1. **Thumbnail réelle** — 3 concepts décrits dans `seo/thumbnail-metadata.md`. Tariq peut générer via Midjourney / DALL-E / Photoshop. Atlas peut produire un brief image-gen détaillé si besoin.
2. **Validation Content ID** — uniquement faisable depuis YouTube Studio (Tariq).
3. **Stream key** — Tariq à 2h.
4. **Decision: auto-restart strict ou soft-recover ?** — voir arbitrage ci-dessus.

---

## Risques connus (à surveiller)

- **WSL2 GPU passthrough** peut casser après une mise à jour du driver NVIDIA Windows. Si `nvcuda.dll` introuvable au démarrage, healthcheck enverra l'alerte mais ne pourra pas auto-fix.
- **Pixabay durations / résolutions** non vérifiables depuis le VPS (WAF 403). Tariq doit confirmer en téléchargeant.
- **Auto-restart Windows update** : prévoir une Task Scheduler "Run whether logged on or not" — si le mot de passe Windows change, le startup auto se casse silencieusement.
- **Layered audio recommandé** (bed continu + thunder one-shots à intervalles aléatoires) — casse le fingerprint Content ID. Pas encore implémenté ; v2 si premier check est clean.

---

## Index des fichiers

```
launch-night/
├── README.md (ce fichier — runbook 2h)
├── assets/
│   └── thunderstorm-assets.md (shortlist vidéo + audio + protocole Content ID)
├── pipeline/
│   ├── stream-thunderstorm.sh (supervisor ffmpeg + auto-restart)
│   ├── thunderstorm-stream.service (systemd unit)
│   ├── thunderstorm-stream.env.example
│   ├── logrotate.conf
│   └── README-setup.md (install sur WSL2)
├── healthcheck/
│   ├── healthcheck.sh (probe local + YouTube API)
│   ├── thunderstorm-healthcheck.service
│   ├── thunderstorm-healthcheck.timer (every 5min)
│   ├── daily-digest.sh
│   └── README.md
└── seo/
    └── thunderstorm-metadata.md (5 titres, description, 50 tags, 3 thumbs)
```
