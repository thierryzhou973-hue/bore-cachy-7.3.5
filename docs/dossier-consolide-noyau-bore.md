# Dossier consolidé — noyau BORE 7.3.5-2, mesures et infrastructure

Écrit le **22/11/2026** à la demande de Thierry : « tout stocker, parce que tu vas oublier ».
Chaque ligne porte sa preuve ou sa mention **NON VÉRIFIÉ**. Rien n'est estimé sans le dire.

---

## 1. But et état du projet

Objectif : un noyau **« v6 »** = sixième version du projet, pas un Linux 6.x. Base retenue :
**CachyOS 7.3.5-2**, identique à la version installée, pour qu'un A/B ne change **que les réglages**.
La cible 6.18 LTS a été **abandonnée** (plus ancienne, elle polluerait la mesure).

État réel au 22/11 : **aucun bzImage v6 n'existe.** Aucune compilation n'a été lancée. Tout ce qui
suit est de la préparation vérifiée, pas un résultat.

---

## 2. Base technique vérifiée

| Élément | Valeur | Preuve |
|---|---|---|
| Tarball source | 269 820 095 octets, lisible | `stat` + `tar -tzf` |
| Patch CachyOS | 44 890 o, **47 hunks, 14 fichiers** | `grep '^diff --git'` |
| `kernel/sched/bore.c` | 15 289 o (généré par le patch) | `ls -l` |
| `include/linux/sched/bore.h` | 2 654 o | `ls -l` |
| Application du patch | **47/47 hunks** après correction | `patch -p1`, exit 0 |

**La correction indispensable** : le hunk de `kernel/futex/waitwake.c` attendait
`hrtimer_sleeper_task_get(timeout)` ; l'arbre 7.3.5-2 vanilla expose `timeout->task`.
Substitution d'une ligne de contexte, sémantique identique. Sans elle, le patch échoue.

---

## 3. Les huit paramètres de BORE (lus dans `bore.c`, lignes 12-20)

| Variable | Défaut | Ce qu'elle règle |
|---|---|---|
| `sched_bore` | 1 | activation générale du modèle de burst |
| `sched_burst_inherit_type` | 2 | mode d'héritage de la pénalité entre tâches liées |
| `sched_burst_protect_slice_lv` | 1 | niveau de protection du slice des tâches interactives |
| `sched_burst_smoothness` | 1 | lissage de la montée de pénalité (décalage binaire) |
| `sched_burst_penalty_offset` | 24 | tolérance avant qu'un burst ne soit pénalisé |
| `sched_burst_penalty_scale` | 1536 | pente de conversion burst → pénalité |
| `sched_burst_cache_lifetime` | 75 000 000 | durée de vie du cache d'héritage (unités internes) |
| `sched_credit_cap_us` | 16 000 | plafond du crédit de sommeil, **16 ms** |

Mécanisme clé, prouvé : `bore_credit_ns()` (ligne 56) plafonne le crédit à 16 ms. Un réveil ne peut
donc **jamais** capitaliser plus de 16 ms d'endormissement, quelle que soit la durée réelle.

**Coût d'un changement à chaud** : ces variables ne sont pas de simples entiers. Les basculer appelle
`readjust_all_task_weights`, qui reparcourt **toutes les tâches** sous `tasklist_lock` en écriture.

---

## 4. Configuration du noyau (relevée dans la config CachyOS)

`HZ_300=y` · `NO_HZ_FULL=y` sans `nohz_full=` (**équivalent NO_HZ_IDLE**) · `PREEMPT=y` +
`PREEMPT_DYNAMIC=y` · `RCU_NOCB_CPU=y` · `MAXSMP=y` (`NR_CPUS=8192`) · `SCHED_CORE=y` ·
`KFENCE=y` · `RANDOMIZE_BASE=y` · `X86_INTEL_PSTATE=y` · `GENERIC_CPU=y` / `X86_64_VERSION=1`.

Cible de compilation imposée : **`-march=goldmont-plus -mtune=goldmont-plus`**, LTO désactivé,
`CONFIG_RUST=n`. Interdits : `-march=native`, `x86-64-v3` — Goldmont Plus **n'a pas AVX2**
(vérifié sur le poste : `avx présent ? NON`).

Rebuild de même version : **pkgrel distinct obligatoire**, ancien paquet conservé.

---

## 5. Ce qui est mesuré sur le poste (22/11, audit lecture seule)

| Mesure | Valeur | Interprétation |
|---|---|---|
| Batterie pleine | 25,89 Wh (74 % du neuf : 35 Wh) | usure : 577 cycles |
| Puissance instantanée | 5,94 W | autonomie théorique ≈ **4,36 h** à ce régime |
| Énergie restante | 8,9 Wh | 34 % |
| Veille | `s2idle [deep]` | **deep disponible ET sélectionné** |
| ASPM | `[default] performance powersave powersupersave` | levier disponible, **non appliqué** |
| Audio | `power_save=10` | déjà en place |
| NVMe | APST 100 000 µs, `runtime unsupported` | défaut confirmé |
| USB | autosuspend 2 s, périphériques `auto` | déjà armé |
| GPU i915 | PSR / FBC / RC6 **absents** | aucun paramètre à toucher en 7.3.5 |
| Écran | 10 667 / 21 333 = **50 %** | point de départ du levier « extinction 120 s » |
| CPU | `intel_cpufreq` + `schedutil`, `intel_pstate=passive`, 2,69 GHz | conforme |

**Gains prouvés à ce jour : aucun.** Le seul gain mesuré dans l'historique du projet est celui du
noyau Android annoncé dans `uname` : **gain de performance non vérifié** — aucune mesure ne le prouve.

---

## 6. Ce que les dix agents ont trouvé (run `agents-run-bore2`, 162,2 s, 10/10)

**Prouvé dans le code** : formules `log2p1`, `calc_burst_penalty`, `rescale_slice`, `bore_credit_ns` ;
bornes `SAMPLE`/`SCAN` ; cache empaqueté lu/écrit en `READ_ONCE`/`WRITE_ONCE` ; hooks fork, tick, sommeil.

**Risques** :
- division par zéro possible dans la LUT si `i == 0` est indexé (cas `count==0`) ;
- comportement indéfini si `fp == 0` (`>> 64`) ou si `shift >= 32` ;
- course sur `bore_credit_ns` et sur le cache, hors verrou ;
- sous-estimation du burst par troncature `SAMPLE`/`SCAN` ;
- bascules sysctl incohérentes pendant que des tâches tournent.

**Désaccords non tranchés** (à relire dans le fichier complet, pas dans un extrait) :
- `update_penalty` : « coupé » contre « fin prouvée » — la seconde lecture tient ;
- `binary_smooth` : montée lissée mais **descente immédiate** (pas symétrique) ;
- `inherit_from_ancestor_hub` : « remonte les ancêtres » contre « descend les enfants » — la descente
  mono-enfant est la version étayée ;
- ordre d'initialisation de la static key du crédit : non tranché.

**Limite du run** : exigence de citer les lignes, résultat **0 citation**. Complétude prouvée,
traçabilité non prouvée.

---

## 7. Infrastructure et accès

| Accès | Valeur | État |
|---|---|---|
| Tunnel SSH poste | `thierry@bore.pub`, port **51736** | actif, clé acceptée |
| Port après reboot | variable, publié sur ntfy | canal `equipe-thierry-7f3c9a1e5b2d84c6` |
| Claude Code (poste) | **2.1.330** dans `~/.npm-global/bin` | installé, non authentifié |
| Node / npm poste | v26.13.1 / 12.2.3 | piège : `--allow-scripts` requis |
| Instabox | `m_agq5mchkl7hdgega5ecvfe3dp4`, 4 vCPU / 8 Go / 17 Go libres | **clé `ibk_` absente de ce VM** |
| 9router | 127.0.0.1:20128 | **arrêté**, 0 fournisseur |
| FreeLLMAPI | :3001 | **arrêté**, aucune clé |
| Simular box | `cb-874e4cae480a`, 2 vCPU / 3,8 Go | réservé au navigateur |

**Point non vérifié** : `uname` du poste annonce `5.10.198-android13`. Deux hypothèses se sont
affrontées sans preuve (`/proc/1/comm` et `/proc/version` jamais relevés) : noyau d'identité Android
posé volontairement, ou conteneur/changement d'amorçage. **À trancher par mesure**, pas par affirmation.

---

## 8. Outils à coût zéro (remplacent `create_agent`, qui facture)

```bash
cd outils
./agents-libres.py --demande "…" --n 10 --vagues 2      # découpage + exécution + synthèse
./agents-libres.py --taches taches.json --vagues 2
./agents-libres.py --reprendre agents-run/<date>
```

Mesures : 10 agents = **107 s** (v1) et **162 s** (v2) ; 2 agents simultanés maximum.
Chaque run écrit `rapport.md` par agent, `manifeste.json` après chaque agent, `ETAT` à la fin.
Notification ntfy sur `equipe-thierry-7f3c9a1e5b2d84c6`.

**Règle de visibilité, chèrement acquise** : je ne vois un run que si je l'attends dans ma réponse.
Une alarme planifiée ne coûte pas plus qu'un message de Thierry — mais elle coûte un tour. Donc :
**j'attends, je vérifie, je rends.** Pas de réveil planifié, Thierry ne veut aucun point dépensé.

---

## 9. Faux pistes et refus assumés

- 25 % de gain global : **impossible**, déjà réfuté avec preuve arithmétique.
- `mitigations=off` : les −36 % sur les syscalls venaient de là, pas du noyau ; réglage déjà en place.
- `page-cluster=0` : déjà le défaut de l'arbre.
- `CONFIG_NO_HZ_FULL=y` seul : ne change rien sans `nohz_full=`.
- Pooling de comptes (OmniRoute), jetons Kiro dans un routeur, `Cursor Forge`, faux statut étudiant,
  contournement de Cloudflare : refusés.

---

## 10. Ce qui reste ouvert

1. Récupérer la clé `ibk_` pour lancer le build sur Instabox.
2. Compiler le v6 et **mesurer le temps de compilation réel** — le seul chiffre qu'on n'a pas.
3. Trancher les trois désaccords des agents en relisant `bore.c` complet.
4. Tester ASPM `powersave` (réversible) et la veille `deep` sur 3 cycles.
5. `/proc/cmdline` illisible par SSH : relever en local pour vérifier `mitigations=off`.

---

## 11. Lot 1 — 20 agents sur le matériel réel (22/11, 334 s, 20/20)

Run `agents-run-pc-lot1/20261123-032148`. Coût : 0 point. Objet : leviers autonomie, fluidité,
performance et réactivité **pour ce poste précis**, pas pour un noyau générique.

### Verdict des agents : aucun levier n'est prouvé

Toutes les références manquent (`p99`, IOPS, consommation par levier). Ils refusent donc de chiffrer
un gain non mesuré. C'est le bon comportement, et c'est la conclusion à retenir : **on n'a pas de
baseline, donc on n'a pas de gain.**

### Ce qui est établi par ce lot

| Fait | Conséquence pratique |
|---|---|
| `HZ=300` ⇒ granularité **3,33 ms** | tout seuil sous la milliseconde exige `ftrace`, pas le tick |
| Batterie à 74 % ⇒ **≈19,2 Wh utiles** | ne jamais calculer l'autonomie sur 25,89 Wh |
| 2 cœurs / 2 threads, **sans SMT** | les gains de parallélisme sont structurellement limités |
| Repos mesuré **5,94 W** | seuil ASPM : **0,25–0,30 W**, en dessous c'est du bruit |

### Ordre d'attaque recommandé (convergent)

1. **Baseline d'abord** : `p99` réveil→switch, frame time, `power_now`, 10 minutes au repos.
2. **Autonomie** : ASPM `powersave`, puis Wi-Fi. Seuil **0,25–0,30 W**, retour arrière sur AER/lien down.
3. **Latence** : un seul tunable BORE à la fois, décision sur `p99` **et** débit batch.
4. Si les leviers divergent → **garder les défauts**. Ne pas empiler des réglages non prouvés.

### Désaccords à trancher par la mesure, pas par l'avis

| Paramètre | Camp A | Camp B |
|---|---|---|
| `cache_lifetime` | 40–50 ms (frappe non écrasée) | 150 ms (burst survit aux pauses) |
| `HZ` | 1000 (latence) | 100 (autonomie) |
| `penalty_scale` | 2048 (protéger l'interactif) | 1024–1280 (protéger le batch) |
| `protect_slice_lv` | 1 → 0 | 1 → 2 si 0 échoue |
| `smoothness` | 1 → 2 | 1 → 0 |

Aucun de ces désaccords ne se règle par un raisonnement : chacun demande une mesure avec son seuil.

### Protocole prêt à exécuter (une soirée, sans risque)

1. `cat /sys/class/power_supply/BAT0/power_now` toutes les 10 s pendant 10 min, machine au repos,
   écran à luminosité fixe → moyenne `P0`.
2. `echo powersave > /sys/module/pcie_aspm/parameters/policy`, même mesure → `P1`.
3. Retenu si `P0 − P1 ≥ 0,25 W` **et** aucun `AER`, aucun `link down` dans `dmesg`. Sinon revert.
4. Latence : compilation `-j2` en fond, frappe chronométrée, `p99` sur 100 réveils, un seul tunable
   BORE modifié par essai.
5. Tout chiffre publié doit être comparé à la dispersion de 3 passes, pas à une seule.

### Lots restants pour arriver à 100 agents (4 × 20, ~5 min chacun, 0 point)

- **Lot 2** : `mm/` et pression mémoire (swap, watermarks, vmscan, zram/zswap), IO NVMe, writeback.
- **Lot 3** : `kernel/time` et tickless, cpuidle, RCU nocb, préemption complète, IRQ affinité.
- **Lot 4** : i915 (PSR/FBC absents), écran et backlight, audio HDA, USB, thermique et throttling N4020.
- **Lot 5** : réseau sans fil, IPv6, MTU, et protocole final de mesure (grille de décision).

---

## 12. Lot 2 — 20 agents sur la mémoire et l'I/O (22/11, 308 s, 20/20)

Run `agents-run-pc-lot2/20261123-033324`. Coût : 0 point. Même verdict de méthode : **aucun réglage
ne doit être appliqué sans référence mesurée**.

### Ce qui est arithmétiquement solide

- 8 Go, 2 cœurs, 5,94 W au repos, **19,16 Wh utiles → ≈3,2 h d'autonomie**.
- Garde-fou de conso : **≈6,4 W** au-delà duquel l'autonomie s'effondre sous 3 h.
- HZ=300 et les défauts BORE sont jugés **adaptés** à ce matériel.

### Les contradictions du lot 2, toutes non tranchées

| Sujet | Position A | Position B |
|---|---|---|
| zram | zstd (majoritaire) | lz4, car 2 cœurs sans AVX2 |
| Taille zram | 2 Go | 3–4 Go (25–50 % de RAM) |
| `swappiness` | 10 | 100 obligatoire avec zram (10 annulerait le levier) |
| `page-cluster` | 0 ou 4 | 3 (défaut), effet jugé nul sur zram |
| Dirty | pourcentages 5/10 % | octets absolus 64M/256M, seuls adaptés à un UMIS lent |
| THP | `always` | `madvise` |
| Ordonnanceur I/O | `none` | `mq-deadline` |
| cgroups | `memory.low` | `memory.min` (interdit sans mesure par un camp) |
| Préemption | `full` | laisser `voluntary` |
| HZ | 1000 | garder 300 |

### Seuils proposés, tous non calibrés sur ce poste

PSI `full` ≥ 5–10 % · `p99` swap-in < 5 ms · `p99` frame time −1 ms · hit zswap > 90 % ·
conso cible < 5,0–5,5 W. Ce sont des heuristiques génériques : à recalibrer avant tout usage.

### Conséquence pratique

Le seul levier **à la fois réversible et rentable** identifié par les vingt agents est la
**configuration zram** — et elle exige deux mesures avant décision : coût CPU du codec (seuil
> 4 ms/Mo) et taux de hit effectif. Sans ces deux chiffres, ajouter zram ne fait que déplacer le coût.

---

## 13. Lots 3 à 5 — 60 agents sur tickless, énergie/écran, réseau (22/11, 1 815 s + 828 s)

Runs `agents-run-pc-lot345/20261123-034551` et `agents-run-pc-lot4b/20261123-042122`. Coût : 0 point.

**Bilan réel : 58 agents utiles sur 60**, pas 60. Huit ont expiré à 300 s pendant la troisième vague :
**8 en parallèle saturent le fournisseur gratuit** — ce n'était pas une erreur de contenu mais une
limite de débit. Relancés par deux, 6 sur 8 ont abouti ; les deux derniers sont restés muets.
Enseignement opérationnel : **4 agents simultanés maximum**, 8 est au-delà du supportable.

### Seuils concrets sortis par ce lot (les seuls chiffres exploitables)

| Levier | Seuil qui tranche | Méthode |
|---|---|---|
| `nohz_full=1` | cœur isolé **≤ 20 IRQ / 60 s** | delta `/proc/interrupts` (timer/local) |
| `rcu_nocbs` | p99.9 cyclictest **≥ +10 µs** sinon désactiver | cyclictest 10 min |
| `mitigations=off` | **≥ 0,30 W** gagnés, sinon garder `auto` | 2 × 15 min, Δ`energy_now`/RAPL |
| Consommation idle | **≥ 0,20 W** (≈ +7 min sur 19,16 Wh) | Δ`energy_uj` sur 600 s, 3 passes |
| Turbo | base **1,1 GHz** vs rafale **2,8 GHz**, marge conso **0,46 W** | charge CPU fixe, Δénergie |
| IRQ + compilation | GUI/input sur CPU1 isolé, `make` sur CPU0 (`taskset -c 0`) | latence de réveil |
| Fluidité | **p99 / p99.9 du frame time**, jamais le FPS moyen | `drm_vblank`, histogramme |
| Veille | `deep` validé si 3 reprises sur 3, décharge inférieure | `/sys/power/suspend_stats` |

### Ce qu'il faut retenir, et qui change la stratégie

- **Marge énergétique totale : 0,46 W** (6,4 − 5,94). Tout levier qui promet moins de 0,20 W est
  indistinguable du bruit sur cette machine. C'est la contrainte dure, et elle est arithmétique.
- **Thermique** : régulation dès ~90–95 °C (DTS 105 °C − offset PROCHOT). Sur châssis faiblement
  dissipé, `-j2` soutenu peut throttler : c'est un plafond de performance réelle, pas un réglage.
- **Veille `deep` sur Gemini Lake** : les pannes connues sont écran noir i915/PSR, timeout APST NVMe,
  ports xHCI perdus. Donc `deep` n'est pas « gratuit » : il faut un protocole de retour.
- **`nohz_full` et `rcu_nocbs`** ne se jugent pas à l'impression, mais sur des deltas d'IRQ et des
  p99.9. Sans ces traces, les activer revient à croire.

### Règle de mesure consolidée (les trois lots convergent dessus)

1. Trois passes minimum, comparer au **min–max de dispersion**, jamais à une passe unique.
2. Un seul réglage modifié par essai, retour arrière vérifié avant l'essai suivant.
3. Tout gain publié doit être **≥ 0,20–0,30 W** (énergie) ou **≥ 10 % de p99** (latence), sinon « non démontré ».
4. `HZ=300` plafonne la résolution à 3,33 ms : tout seuil plus fin exige `ftrace`, pas le tick.

---

## 14. Leviers obtenus en direct (Claude Code + opencode, 22/11)

Claude Code local **fonctionne** : il est câblé sur une passerelle et répond en `deepseek-v4-1-flash-1017`
(Claude Code affiche un avertissement de modèle non reconnu, sans conséquence).

### Consensus entre Claude Code et DeepSeek free

| Levier | Commande | Seuil qui valide | Retour arrière |
|---|---|---|---|
| **ASPM `powersupersave`** | `echo powersupersave > /sys/module/pcie_aspm/parameters/policy` | repos **≤ 5,69 W** (−0,25 W) et **0** ligne `AER`/`nvme reset` en 30 min | `echo performance > …/policy` |
| **Veille `deep`** | `echo deep > /sys/power/mem_sleep` | veille **−25 %** (ou ≤ 0,5 %/h) et reprise OK sur 3 cycles | `echo s2idle > /sys/power/mem_sleep` |

Claude Code est plus strict sur l'ASPM : **≤ 5,40 W** (−0,54 W). Les deux exigent le contrôle `dmesg`
et un retour arrière immédiat — c'est le signe que le risque NVMe est réel sur ce chipset.

### Troisième levier : divergence, non tranchée

- **Claude Code** : `intel_pstate` en `active` + `EPP balance_power` sur les deux policy. Seuil : repos
  ≤ 5,5 W **et** p99 cyclictest dégradé ≤ 10 %. Risque : plantage au boot sans persistance.
- **DeepSeek free** : `nmi_watchdog=0` + `dirty_writeback_centisecs=3000`. Seuil : wakeups/s −20 %
  ou repos ≤ 5,79 W. Risque : perte de détection hardlockup et jusqu'à 30 s de données non écrites.

Les deux sont testables séparément ; **aucune mesure n'a pu être faite**, le poste étant éteint.

Deux modèles sur trois n'ont rien produit d'exploitable : `flint-40b-free` est revenu vide,
`glm-5.3-flash-free` en erreur « Model is unavailable ». Le palier gratuit n'est pas homogène.

## 15. État consolidé du projet (2026-11-23) — v2, remplace les sections antérieures en cas de contradiction

Cette section remplace tout ce qui précède en cas de contradiction. Chaque ligne porte
sa preuve ou sa mention **NON VÉRIFIÉ**.

### 15.1 Objectif et dépôt

Noyau CachyOS 7.3.5-2 + BORE pour un Lenovo V15 IGL (Celeron N4020, UHD 600), avec
validation de démarrage **sans toucher l'entrée par défaut du bootloader**.

- Dépôt : `github.com/thierryzhou973-hue/bore-cachy-7.3.5`
- Sources : `cachyos-7.3.5-2.tar.gz`, 258 Mo, sha256 `bb22ad99…2e07` — conforme
- Patch principal : 47/47 hunks
- Correctif `fair.c` : appliqué manuellement dans le premier build (en-têtes non standards),
  régénéré proprement au commit `c5fc4b2`, testé `patch -p1` jusqu'à identité octet pour octet
- Script de mesure : corrigé au commit `11f16d2` (l'ancien concluait « REVERT » à tort)

### 15.2 Matériel et options retenues

N4020 : Goldmont Plus, 2C/2T, 1,1→2,8 GHz, 6 W, SSE4.2 / AES-NI / PCLMUL / CRC32 / SHA,
**pas d'AVX**, pas de HT, pas de HWP. UHD 600 Gen9 (12 EU), 4–8 Go DDR4.

`config-lenovo-v15-igl-n4020` : `X86_NATIVE_CPU=y` (`-march=goldmont-plus`),
`NR_CPUS=8192→8`, `MAXSMP=n`, `LOCALVERSION="-lenovo-v15-igl"`.
Déjà optimaux : BORE + `MIN_BASE_SLICE_NS=1600000`, `PREEMPT=y`, `HZ=1000`, schedutil,
intel_idle, i915 en module, zram/zswap/BFQ. Runtime conseillé : `i915.enable_guc=2`
(HuC seul ; `3` activerait une soumission GuC absente de Gen9), `compress=zstd:3` sur btrfs.
ASPM : à mesurer avant activation. `CONFIG_RUST` et le patch d'identité Android 13 écartés.

### 15.3 Accès distant

- `ssh-bore-audit/` : bore.pub + ntfy (topic `equipe-thierry-…`, port 51736). 6 fichiers
  audités : **2 bugs de sécurité élevés** (clé privée copiée jamais nettoyée dans `/tmp` ;
  anti-brute-force inopérant, bore forwardant depuis `127.0.0.1` → IP source unique),
  4 moyens/bas (regex au lieu de `grep -F`, `PermitRootLogin`, confinement factice,
  topic devinable). Version corrigée livrée. Limite structurelle : relais public tiers.
- `ssh-leger/` : dropbear (~200 Ko) + autossh vers VPS, modes `reverse`/`direct`,
  systemd et clés épinglées.
- **Le tunnel annoncé actif était faux** : port 51736 fermé, aucun ntfy depuis 2 h.
  La config n'a pas été récupérée par ce chemin (elle l'a été par `extract-ikconfig`
  sur le paquet officiel, voir 15.6).
- Un token GitHub a transité par un chat : **à révoquer**.

### 15.4 Build v1 — échec, cause réelle

`bzImage` de 3,3 Mo issu d'un `x86_64_defconfig` (gcc 13.3) : 1 040 objets, **zéro**
ext4/btrfs/nvme/usb_hcd. Non bootable. La config cible existait depuis 07:56 ; le build
correct (`build3.log`, 19 170 objets) a été **interrompu** sur `BTF .tmp_vmlinux1`.
Diagnostic correct : ce n'est pas la config qui manquait, c'est le build qui était périmé.

Trois affirmations du rapport v1 corrigées : BORE bien compilé (27 symboles,
`update_burst_cache` absent car `static inline`) ; non-bootabilité confirmée mais
mal expliquée ; tunnel inexistant. Comparaison `bore.o` 24 648 / 14 872 octets :
le build de contrôle était **gcc 11.4 + defconfig**, pas clang.

### 15.5 Build v2 — livré et testé en QEMU

Config correcte. Deux blocages franchis : `pahole` tué par l'OOM (conteneur limité à
**8 Gio**, `vmlinux` à 1,1 Go avec DWARF/BTF) → `DEBUG_INFO_NONE=y` ; `zstd` absent
(`Error 127`), installé. Piège `-march` évité : machine de build EPYC 9754 AVX-512,
`KCFLAGS="-march=goldmont-plus -mtune=goldmont-plus"` appliqué après `KBUILD_CFLAGS` ;
contrôle : aucune instruction AVX hors routines assembleur à sélection runtime.

Preuve QEMU : noyau `7.3.5-lenovo-v15-igl`, `fs: ext4 btrfs`, `block: nvme0n1`,
`sched_bore: 1`, **montage ext4 d'un fichier écrit hors VM** réussi, poweroff propre.
Confirmé aussi en virtio (`vda`) et `xhci_hcd` détecté.
`System.map` : 245 436 symboles (ext4 3 858, btrfs 5 140, nvme 1 306, usb_hcd 99,
scsi 1 210, sd 222, ahci 242, tcp 2 396).

### 15.6 Faits établis par extraction des paquets officiels (mesurés)

- `scripts/extract-ikconfig` sur le `vmlinuz` officiel a rendu la config authentique
  (`CONFIG_IKCONFIG=y`), 12 849 lignes : `docs/config-cachyos-bore-7.3.5-2` dans le dépôt.
- **Le noyau `linux-cachyos` standard n'a pas BORE** ; `linux-cachyos-bore` l'a.
  Différence entre les deux paquets : exactement `CONFIG_SCHED_BORE=y` et
  `CONFIG_MIN_BASE_SLICE_NS=1600000`.
- Config officielle : `CONFIG_NVME_CORE=m`, `CONFIG_CC_IS_GCC=y`, `CONFIG_GENERIC_CPU=y`,
  `PREEMPT=y`, `HZ=1000`, `DEBUG_INFO_BTF=y`, `DEBUG_INFO_BTF_MODULES=y`,
  `MODULE_SIG=y`, `MODULE_SIG_ALL=y`, `MODULE_SIG_KEY="certs/signing_key.pem"`.

### 15.7 Risques non vérifiés à trancher avant installation

1. **Secure Boot** — le build v2 signe ses 6 591 modules avec une clé jetable générée
   localement, et le noyau lui-même n'est signé par aucune clé inscrite. Si Secure Boot
   est actif, le boot échoue. Vérification : `mokutil --sb-state`. **NON VÉRIFIÉ.**
2. **Boot réel sur le Lenovo** — QEMU ne valide ni i915 (UHD 600), ni ACPI de la machine,
   ni trackpad I2C, ni audio, ni firmware. **NON VÉRIFIÉ** : aucun boot sur le matériel.
3. **Perte de BTF** — au-delà de `bpftrace` CO-RE, `DEBUG_INFO_NONE` prive des
   ordonnanceurs `scx_*`, donc de l'alternative à BORE pour la réactivité. Compromis
   assumé, mais il empêche une comparaison A/B honnête.
4. **Gain de performance ou d'autonomie** — **AUCUNE MESURE**. Le poste est resté éteint
   (port 51736 fermé, ntfy muet). `outils/mesure-gains-noyau.sh` attend un PC allumé.

### 15.8 Procédure d'installation sûre (non exécutée)

```bash
# 1. contrôle Secure Boot AVANT tout
mokutil --sb-state

# 2. noyau alternatif, sans écraser l'existant
sudo make modules_install
sudo cp arch/x86/boot/bzImage /boot/vmlinuz-linux-lenovo-v15-igl
sudo mkinitcpio -k "$(make -s kernelrelease)" -g /boot/initramfs-linux-lenovo-v15-igl.img

# 3. entrée de bootloader séparée, l'entrée par défaut reste intacte
# 4. boot sur cette entrée, puis :
sudo bash outils/mesure-gains-noyau.sh
```

Tant que l'étape 4 n'a pas produit deux séries de chiffres (P0 et P1), ce noyau reste
une hypothèse compilée, pas un gain.
