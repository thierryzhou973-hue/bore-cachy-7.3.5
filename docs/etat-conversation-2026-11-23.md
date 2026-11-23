# État complet de la conversation — 2026-11-23

Document de reprise. Il remplace tous les résumés antérieurs en cas de contradiction.
Chaque ligne porte sa preuve, ou la mention **NON VÉRIFIÉ**.

## 1. Objectif

Noyau **CachyOS 7.3.5-2 + BORE** adapté à un **Lenovo V15 IGL** (Celeron N4020, UHD 600),
validé par un démarrage réel, sans toucher l'entrée par défaut du bootloader — puis
**mesure** des gains (autonomie, réactivité), pas des promesses.

Dépôt public : `github.com/thierryzhou973-hue/bore-cachy-7.3.5`

## 2. Faits mesurés (reproduits, pas déduits)

| Fait | Preuve |
|---|---|
| Patch CachyOS+BORE | 47/47 hunks, exit 0 |
| Patch BORE **tel quel** | **ne compile pas** : `normalized_sysctl_sched_base_slice` absent de la branche `CONFIG_SCHED_BORE` |
| Correctif `fair.c` | régénéré en `a/` `b/`, testé `patch -p1`, résultat **identique octet pour octet** au fichier qui a compilé |
| `kernel/sched/bore.o` | compile, 14 872 octets (gcc 11.4, defconfig) |
| `kernel/sched/built-in.a` | compile, 0 erreur |
| Noyau standard `linux-cachyos` | **n'a pas BORE** (0 occurrence dans sa config) |
| Variante `linux-cachyos-bore` | l'a — écart avec le standard : 2 options (`SCHED_BORE=y`, `MIN_BASE_SLICE_NS=1600000`) |
| Config officielle | extraite du `vmlinuz` par `extract-ikconfig`, 12 849 lignes, versionnée dans le dépôt |
| Config officielle : `NVME_CORE=m`, `CC_IS_GCC=y`, `GENERIC_CPU=y`, `HZ=1000`, `PREEMPT=y`, `BTF=y`, `MODULE_SIG_ALL=y` | extraite |
| Build v2 (par l'agent Workbuddy) | QEMU : `fs: ext4 btrfs`, `nvme0n1`, `sched_bore: 1`, montage ext4 d'un fichier écrit hors VM |
| `System.map` v2 | 245 436 symboles (ext4 3 858, btrfs 5 140, nvme 1 306, usb_hcd 99) |
| Build v1 (3,3 Mo) | issu d'un `defconfig` : **zéro** ext4/btrfs/nvme/usb — non bootable |
| BORE dans le binaire | 27 symboles `bore` ; `update_burst_cache` absent car `static inline` |

## 3. Coûts réellement facturés (API freemodel)

| Appel | Tokens in/out | Coût |
|---|---|---|
| deepseek-v4.1-flash ×2 | 3 189 / 617 | 0,00023 € |
| claude-fable-5-1 ×1 | 4 464 / 4 540 | 0,186 € |
| claude-opus-5-5 ×1 | 3 188 / 2 304 | 0,059 € |
| **Total des essais** | | **≈ 0,25 €** |

Taux utilisé : 0,9176 $/€. Tarifs passerelle par 1 M : deepseek 0,056 $/0,112 $ ;
opus-5-5 8,30 $/16,61 $ ; fable-5-1 15 $/30 $.

Mesure sur extrait identique (3,8 Ko de `bore.c`) : fable 9 004 tokens / 16,0 s ;
opus 5 492 tokens / 12,3 s. **Opus = 61 % des tokens et 32 % du coût de Fable**, réponse
de qualité égale (les deux citent correctement les lignes 56 et 63).

## 4. Modèles en service

- Fournisseur `freemodel` (OpenAI-compatible) déclaré dans `~/.config/opencode/opencode.json` :
  `claude-opus-5-5`, `claude-fable-5-1`, `deepseek-v4.1-flash`.
- Tests passés : Opus a répondu, DeepSeek a répondu.
- **Limites constatées** : DeepSeek coupe à 30 s au-delà de ~2 Ko de code ; Fable ignore
  `max_tokens` et gonfle la sortie (4 540 tokens pour une réponse de 5 lignes).
- Clé Coarena (`~/.coarena_key`, 600) utilisée par un agent antérieur : `pont-coarena.py`
  route deepseek depuis cette VM, GPT-6 Luna depuis la box (modèles premium bloqués
  depuis l'IP de la VM). **Non re-testé depuis.**

## 5. Clés et secrets

Trois clés ont transité par la conversation (passerelle de modèles, GitHub, Coarena).
Elles sont stockées hors dépôt, dans des fichiers à permissions `600`.

Règle appliquée : **aucune clé dans la mémoire de préférences** (elle est réinjectée dans
le prompt de chaque session) et **aucune clé dans un dépôt**, public ou privé.
Les trois sont à révoquer une fois le projet stable.

## 6. Dépôt privé `agent-bridge` (audité)

Relais HTTP entre agents : `/a2a`, `/api/messages`, `/api/jobs`, `/api/workers`, `/mcp`.
Identités : `admin`, `codex`, `claude`, `cloud-worker`, `chatgpt`, `openai-agent-worker`.

**Solide (vérifié dans le code)** : jetons hachés + `hmac.compare_digest` ; aucun secret en
dur ; ni `eval`, ni `pickle`, ni `shell=True` ; `USER 10001`, `read_only`, `cap_drop: ALL`,
`pids_limit 64`, `mem_limit 512m` ; liaison `127.0.0.1:8787`.

**Manquant** : aucun TLS ; aucune limitation de débit (pas de 429) ; `credentials.txt` en
clair par conception ; **5 tests seulement** alors que quatre fichiers de test sont annoncés ;
aucun hôte durable — le relais n'a jamais tourné.

## 7. Refus maintenus

- Brûler « 100 M de tokens » : 100 M sur fable-5-1 ≈ 1 500–3 000 $ et ~11 000 questions,
  sans produire un seul watt mesuré.
- Promettre « +30 % partout » : aucun noyau ne rend un N4020 30 % plus rapide sur tout.
- Automatiser arena.ai / contourner Cloudflare, pools de comptes.
- Affirmer la bootabilité sur la foi d'un QEMU.

## 8. Non vérifié, à trancher

1. **Secure Boot** : `mokutil --sb-state` — si actif, les 6 591 modules signés par une clé
   jetable et le noyau non signé empêchent le boot.
2. **Boot réel sur le Lenovo** : QEMU ne valide ni i915 (UHD 600), ni ACPI, ni trackpad I2C.
3. **Perte de BTF** : pas de `bpftrace` CO-RE, ni de `scx_*` → pas de comparaison A/B honnête
   contre l'alternative à BORE.
4. **Gain d'autonomie / réactivité** : **aucune mesure**. Poste éteint (canal distant injoignable). `outils/mesure-gains-noyau.sh` attend un PC allumé.
5. **Clé Coarena** : validité actuelle inconnue.
6. **Noyau Android** : deux hypothèses sans preuve (`/proc/1/comm`, `/proc/version` jamais
   relevés).

## 9. Prochaines étapes, dans l'ordre

1. PC allumé → `sudo bash outils/mesure-gains-noyau.sh` (2 × 10 min) → P0/P1 chiffrés.
2. `mokutil --sb-state` avant toute installation.
3. Boot sur l'entrée alternative, jamais en remplacement de l'entrée par défaut.
4. Comparer les chiffres, puis décider : garder, ajuster, ou revenir.
5. Révoquer les trois clés quand le projet est stable.
