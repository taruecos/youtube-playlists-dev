# Discovery — 3 chaînes lives ambient YouTube

**Objectif :** Setup one-time → 100k€/an passif sur 5 ans
**Modèle :** 3 chaînes lives 24/7 (zen, nature, ambient)
**Méthode :** Q&A structuré — Atlas pose, Tariq répond, on adapte
**Outils payants autorisés :** claude code max plan only — pas d'autre dépense soft

---

## Progression
- Total questions prévues : **100**
- Répondues : **23**
- Progression : **23%**

> Sync du 2026-06-09 : reprise complète de l'historique Telegram → décisions de Cat 3 / Cat 4 / Cat 5 / Cat 8 déjà prises mais pas reportées ici, intégrées ci-dessous.

---

## Catégories

| # | Catégorie | Questions prévues | Statut |
|---|-----------|-------------------|--------|
| 1 | Objectifs & contraintes perso | 10 | ✅ closée (5/5 batched) |
| 2 | Niches & positionnement | 15 | ✅ closée (5/5 batched + choix final niche) |
| 3 | Stack technique (streaming/VPS) | 15 | 🟡 partielle (6/15) |
| 4 | Production visuelle | 10 | 🟡 amorcée (1/10) |
| 5 | Production audio | 10 | 🟡 amorcée (2/10) |
| 6 | Algorithme & policies YouTube | 10 | ⏳ à ouvrir |
| 7 | Monétisation (au-delà ads) | 10 | ⏳ à ouvrir |
| 8 | Automatisation & opérations | 10 | 🟡 amorcée (3/10) |
| 9 | Risques & contingence | 5 | ⏳ à ouvrir |
| 10 | Scaling & exit | 5 | 🟡 amorcée (1/5) |

---

## Réponses (live tracking)

### Catégorie 1 — Objectifs & contraintes perso ✅

**Q1 — Capital upfront ?**
0€ cash dispo aujourd'hui. Le VPS existe déjà (atlas-vps, mutualisé avec Atlas bot). Après mois 3 : 100€/mois max d'investissement, **100% marketing** (le soft est déjà payé via claude code max).
→ *Implication :* tout doit tourner sur infra déjà payée en M1-3. Pivot fait (cf. Q11) : on shift vers la tour de Tariq plutôt que atlas-vps.

**Q2 — Heures/semaine sur les 3 premiers mois ?**
0h directes. Claude (Atlas) fait tout : génération contenu, upload, gestion streams, monitoring.

**Q3 — Heures/semaine post-setup ?**
Vraiment 0h. "Je regarde juste le dashboard YouTube".
→ *Risque flaggé :* irréaliste sans tolérance aux pannes. Faut prévoir auto-restart, alertes Telegram, et un mode "Atlas répond aux mails YouTube" si possible.

**Q4 — 100k€ brut ou net ?**
Brut. Pas de focus fiscalité pour l'instant (atlaslaboratory llc encaisse).

**Q5 — Deadline ou seuil d'abandon ?**
Aucun. On suit le plan 12 mois et on tient.
**Bonus — Horizon long :** Tariq a précisé : **setup une fois, ne touche plus pendant 5 ans**. Tout doit être hardened pour vivre 5 ans sans maintenance manuelle.

**Contraintes dures retenues :**
- Budget M1-3 : **0€** (infra déjà payée)
- Budget M4+ : **100€/mois max, 100% marketing**
- Outils payants : **claude code max plan only**
- Intervention humaine cible : **0h/semaine** pendant **5 ans**
- Cible : **100k€ brut/an** atteint courant année 2
- Pas de plan d'abandon — résilience > pivot

---

### Catégorie 2 — Niches & positionnement ✅

**Q6-Q10 — Tous les choix de niche/positionnement (batched)**
**Réponse unique : le ROI décide tout.**
- Pas de préférence personnelle (rain vs forest vs fireplace etc.)
- Pas de préférence diversification vs angles d'une niche
- Pas de préférence audience (sleep/study/meditation)
- Pas de préférence langue
- Pas de préférence niche éprouvée vs émergente

**Q11 — Faceless ?**
Oui, 100% faceless. Aucune intervention humaine à la caméra.

**Q12 — ASMR ?**
Non. ASMR exclu de la shortlist (préférence Tariq).

**Q13 — Choix final niche (data + arbitrage Tariq) :**
> **Pluie + Nature + Forêt** — choix explicite Tariq après shortlist Atlas.
> Combo cohérent : 3 chaînes spécialisées sur des sous-angles de cet univers (ex : `rain only`, `rainforest with thunder`, `forest birds + light rain`). À affiner via étude RPM/CPM avant lancement.

**Contraintes ajoutées :**
- Choix de niche **piloté par data**, pas par goût
- Univers global verrouillé : **eau + végétation + ambient outdoor**
- Atlas doit livrer une étude comparative sous-niches (rain vs forest vs rainforest vs thunderstorm vs fireplace-outdoor) → matrice ROI avant lancement chaîne 2 et 3
- Critères : RPM, CPM, taille audience cible, saturation, temps avant 1000 subs + 4000h

---

### Catégorie 3 — Stack technique (streaming) 🟡

**Q14 — Infra de run ?**
**La tour de Tariq**, pas le VPS. Décision prise après audit capacité : atlas-vps (1 vCPU / 4GB RAM) ne tient pas 3 streams 24/7 + génération AudioCraft. La tour a la puissance pour générer + streamer en local.

**Q15 — Specs tour (validées par audit live) :**
| Composant | Spec |
|---|---|
| OS | Windows 11 + **WSL2** (Ubuntu) |
| CPU | AMD Ryzen 9 7900X — 12 cores |
| RAM | 64 GB |
| GPU | RTX 3060 — 12 GB VRAM |
| Disque libre | 954 GB |
| Réseau | Fibre optique |
| Hostname | `lamachine` |
| User Windows | `lahmo` |
| User WSL2 | `atlas` (uid 1000, sudo NOPASSWD) |

**Q16 — Accès distant Atlas → tour ?**
Tailscale (IP : `100.77.59.19`) + OpenSSH server sur Windows.
Pubkey installée dans `C:\ProgramData\ssh\administrators_authorized_keys`.
Atlas SSH dedans depuis atlas-vps.

**Q17 — Modèle d'exécution stream ?**
ffmpeg en local sur la tour → push RTMP vers YouTube Live. systemd-équivalent (NSSM côté Windows ou service WSL) pour auto-restart 24/7. Pas de RTMP relay intermédiaire.

**Q18 — Setup tour Phase 0 (validé hier, 2026-06-08) :**
✅ `nvidia-smi` dans WSL2 affiche RTX 3060 + 12 GB VRAM
✅ ffmpeg 4.4.2 installé
✅ 954 GB libres
✅ /etc/wsl.conf configuré (default user atlas, systemd activé)
✅ Driver host NVIDIA 576.40 → passthrough WSL 575.55.01 / CUDA 12.9
✅ apt upgrade complet

**Q19 — Stack à compléter (Phase 1+ à valider) :**
- CUDA toolkit 12.4 + venv + PyTorch [pas encore installé]
- AudioCraft (HuggingFace) + dépendances [pas encore installé]
- Pipeline ffmpeg loop vidéo+audio → RTMP YouTube [à coder]
- Service auto-restart 24/7 [à coder]
- Tooling YouTube Data API v3 (upload, gestion playlists) [à coder]

**À ouvrir : Q20-Q28** — débit upload, bande passante long terme, monitoring (Telegram alertes), stockage des assets renderés, GPU thermal sous charge 24/7, fail-over si la tour down, scaling vers chaînes 2 & 3.

---

### Catégorie 4 — Production visuelle 🟡

**Q29 — Source vidéo ?**
"ROI qui décide" (Tariq). Atlas tranche : packs stock royalty-free (Pexels, Pixabay) en M1, génération IA (LTX-Video / Stable Video Diffusion sur la RTX 3060) en M2+ pour différenciation.
Contrainte Tariq : **chaque vidéo doit être unique** (random pipeline visuel).

**À ouvrir : Q30-Q38** — durée loop, résolution (1080p vs 4K), framerate, transitions, branding visuel par chaîne, ratio fixe vs animé, color grading, watermark, packshot end-screen.

---

### Catégorie 5 — Production audio 🟡

**Q39 — Stack audio ?**
**AudioCraft local** (HuggingFace, gratuit) sur RTX 3060 12GB VRAM. Pas de Suno (payant).
Précision Tariq : "même puissance que Suno" pour 0€.

**Q40 — Mix temp en attendant la chaîne live ?**
Source freesound — sample shortlisté pour le live d'attente : **Rain + Rainforest INNORECORDS** (freesound.org/people/INNORECORDS/sounds/457447/), choisi pour le match keywords YouTube haut volume [non vérifié sur les chiffres de volume].

**À ouvrir : Q41-Q48** — durée seamless loop, qualité audio (WAV vs FLAC vs Opus), normalisation LUFS pour YouTube (-14 LUFS), variation entre vidéos d'une même chaîne, mix multi-couches (pluie + tonnerre + oiseaux), licence sample tiers, droit voisin.

---

### Catégorie 6 — Algorithme & policies YouTube ⏳

À ouvrir entièrement. Sujets prévus : repeat content policy (la grosse), seuil de monétisation (1000 subs + 4000h), titres/tags/thumbnails SEO, lives vs uploads (vues comptées différemment), shadowbans, copyright Content ID sur AudioCraft.

---

### Catégorie 7 — Monétisation (au-delà ads) ⏳

À ouvrir. Sujets prévus : memberships, super chats sur lives, merch print-on-demand, sponsoring direct ambient brands, distribution audio Spotify/Apple Music via DistroKid (Tariq a évoqué Spotify playlists).

---

### Catégorie 8 — Automatisation & opérations 🟡

**Q49 — Nombre de chaînes au lancement ?**
1 chaîne en M1, scaling 2 & 3 après validation du pipeline (Tariq confirmé : "on commence avec 1").
État actuel : **1ère chaîne YouTube créée** (Tariq sur YouTube Studio le 2026-06-09).

**Q50 — Mode de gestion multi-chaînes ?**
3 comptes Google distincts (créés au fur et à mesure, pas d'OAuth multi-channel).
YouTube Data API v3 par compte pour l'upload programmatique. Pas encore de tokens générés.

**Q51 — Mode de lancement (live vs uploads) ?**
Hybride : **lives 24/7** (objectif principal) + uploads VOD de 12h tous les 3 jours en seed (mentionné par Tariq, à valider via policy YouTube).

**À ouvrir : Q52-Q58** — cron de génération, file d'attente RTMP, upload queue API, rotation des assets, dashboard monitoring (Telegram ?), CI/CD du pipeline, gestion strikes/DMCA automatisée.

---

### Catégorie 9 — Risques & contingence ⏳

À ouvrir. Sujets prévus : panne tour (downtime ne déclenche pas un strike YouTube ?), Tariq inactif si demande YouTube (verif compte, KYC AdSense), Content ID match sur AudioCraft output, change of YouTube policy mid-vie du projet.

---

### Catégorie 10 — Scaling & exit 🟡

**Q59 — Horizon ?**
**5 ans passifs après setup.** Pas d'exit prévu — c'est une rente, pas un asset à vendre.

**À ouvrir : Q60-Q63** — passage à 5/10 chaînes si ROI validé, recyclage assets entre chaînes, conditions de pivot si 100k€ pas atteint en année 2, héritage / transfert (atlaslaboratory llc).

---

## Décisions verrouillées (résumé)

| # | Décision | Source |
|---|----------|--------|
| D1 | 3 chaînes YouTube faceless | Tariq |
| D2 | Univers niche : pluie + nature + forêt | Tariq |
| D3 | Setup sur la tour (pas le VPS) | Tariq |
| D4 | Stack : Windows + WSL2 + ffmpeg + AudioCraft | Atlas, validé Tariq |
| D5 | Accès : Tailscale + OpenSSH | Tariq |
| D6 | Outils payants : claude code max plan only | Tariq |
| D7 | Budget : 0€ M1-3, 100€/mois marketing M4+ | Tariq |
| D8 | Intervention humaine : 0h pendant 5 ans | Tariq |
| D9 | Lives 24/7 (objectif principal) + VOD 12h en seed | Tariq |
| D10 | 1ère chaîne déjà créée — scaling après validation | Tariq |

---

## Prochain blocker à lever

**Étude comparative sous-niches** (pluie pure vs rainforest vs forest birds vs thunderstorm vs fireplace outdoor) — matrice ROI = (CPM × audience accessible) / (concurrence + time-to-monetization).
→ Tant que pas livré, on peut pas trancher l'angle exact de la chaîne 1 ni shortlister chaînes 2 & 3.
→ Chiffres CPM/RPM/audience à pull live (Social Blade + YouTube search saturation) — **pas de mémoire, tout vérifié**.

## État opérationnel

- ✅ Tour online (Tailscale `100.77.59.19`), SSH OK depuis atlas-vps
- ✅ Phase 0 setup tour (WSL2, ffmpeg, CUDA) validée
- ✅ 1ère chaîne YouTube créée
- ⏳ Stream key YouTube à récupérer (YouTube Studio → Créer → Diffuser en direct)
- ⏳ Phase 1 setup tour : CUDA toolkit + venv + PyTorch + AudioCraft
- ⏳ Étude sous-niches → choix angle chaîne 1
