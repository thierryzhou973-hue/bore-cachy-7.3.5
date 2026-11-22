# bore-cachy-7.3.5 — patch BORE pour CachyOS 7.3.5-2, corrigé

Ce dépôt contient les pièces issues d'un travail de mesure et de compilation
réel sur noyau CachyOS 7.3.5-2 (base Linux 7.3.5, patch CachyOS 47 hunks /
14 fichiers), et le correctif sans lequel le patch **ne compile pas**.

## Ce qui est prouvé

| Élément | État | Preuve |
|---|---|---|
| Patch CachyOS appliqué | 47/47 hunks, exit 0 | `patch -p1 < patchs/bore-fixed.patch` |
| `kernel/sched/bore.o` | compile, 14 872 octets | `make kernel/sched/bore.o` |
| `kernel/sched/` complet avec BORE | compile, 0 erreur | `kernel/sched/built-in.a` |
| Patch BORE **tel quel** | **ne compile pas** | voir `patchs/bore-correctif-fair.patch` |
| Gain mesuré sur la machine cible | **aucun** | pas encore mesuré, PC éteint |

## Le bug corrigé

Dans `kernel/sched/fair.c`, le patch enveloppe `set_protect_slice()` par
`#ifdef CONFIG_SCHED_BORE` mais oublie la même protection dans
`update_protect_slice()`, qui utilise `normalized_sysctl_sched_base_slice`.
Or la branche `CONFIG_SCHED_BORE` ne définit pas cette variable (elle n'existe
que dans le `#else`). Résultat : compilation en erreur.

```
kernel/sched/fair.c:1174:21: error: 'normalized_sysctl_sched_base_slice' undeclared
```

Correctif : utiliser `sysctl_sched_base_slice` quand BORE est actif, comme
`set_protect_slice()` le fait déjà.

## Utilisation

```bash
# 1. base
tar xf cachyos-7.3.5-2.tar.gz && cd cachyos-7.3.5-2

# 2. patch principal puis correctif
patch -p1 < patchs/bore-fixed.patch
patch -p1 < patchs/bore-correctif-fair.patch

# 3. config : BORE actif
scripts/config --enable SCHED_BORE
make olddefconfig

# 4. preuve rapide (2 min)
make -j"$(nproc)" kernel/sched/

# 5. noyau complet
make -j"$(nproc)" bzImage
```

Dépendances : `bc libelf-dev flex bison libssl-dev build-essential cpio`.

## Mesure des gains

`outils/mesure-gains-noyau.sh` mesure la consommation au repos avant/après
passage de l'ASPM en `powersupersave`, avec seuil de gain et retour arrière
automatique.

```bash
sudo bash outils/mesure-gains-noyau.sh
```

## Ce que ce dépôt ne prétend pas

Aucun gain de « +30 % partout » n'est démontré. Un noyau ne change pas le
débit global ; BORE change l'ordre de passage sous charge (latence), et les
réglages changent la consommation. Les chiffres viendront de la mesure,
pas de ce README.

## Journal des corrections

**v1.1** — `erreurs_pcie()` renvoyait `"0\n0"` : `grep -c` écrit `0` sur stdout *et* sort en
erreur, donc le `|| echo 0` ajoutait un second zéro. `[ "$E1" -eq 0 ]` échouait alors avec
« integer expression expected », et le script concluait **REVERT même sans aucune erreur PCIe**.
Corrigé : la fonction renvoie un entier propre, ou `inconnu` si `dmesg` est illisible ; le test
compare des chaînes, et le cas `inconnu` déclenche un retour arrière par prudence.

Trois cas vérifiés en simulation (fausse batterie, fausse politique ASPM, faux `dmesg`) :

| Situation | Attendu | Obtenu |
|---|---|---|
| gain 0,45 W, 0 erreur AER | garder | **GARDE** |
| gain 0,54 W, 1 erreur AER | revenir en arrière | **REVERT** |
| `dmesg` illisible | revenir en arrière par prudence | **REVERT (dmesg illisible)** |

**v1.2** — `BAT` et `ASPM` surchargeables par variable d'environnement, pour tester sans
toucher au système.

## Obtenir les sources

Le tarball CachyOS 7.3.5-2 (258 Mo) n'est pas versionnable sur GitHub :

```
https://aka.doubaocdn.com/s/xI8Lo2AqiJ
taille   : 269 820 095 octets
sha256   : bb22ad99e1042fae883bab71366f8339367b74c045004fe92ad4923339092e07
```

Vérification avant usage :

```bash
sha256sum cachyos-7.3.5-2.tar.gz   # doit correspondre à la valeur ci-dessus
```

## Build dans un sandbox qui hiberne

Les environnements d'exécution éphémères perdent un build noyau en cas d'inactivité.
Pour que le build survive, il faut le détacher de la session :

```bash
nohup make -j"$(nproc)" bzImage > build.log 2>&1 &
echo $! > build.pid          # pour retrouver le processus
```

puis sonder `build.log` / `build.pid` à intervalle régulier plutôt que d'attendre dans
la session. Un build defconfig sur 2 vCPU prend de l'ordre d'une à plusieurs heures.

## Correctif : testé en `patch -p1` (v1.1.1)

La première version du correctif avait un en-tête non standard
(`sources-bore/tree/...` + chemin absolu) : `patch -p1` ne la trouvait pas.
Régénéré avec `diff -u --label a/... --label b/...`, puis **testé en chaîne** :

```bash
tar xzf cachyos-7.3.5-2.tar.gz -O cachyos-7.3.5-2/kernel/sched/fair.c > kernel/sched/fair.c   # vanilla
patch -p1 < patchs/bore-fixed.patch              # hunk fair.c, 23 hunks
patch -p1 < patchs/bore-correctif-fair.patch     # doit passer sans offset
```

Résultat mesuré : le `fair.c` obtenu est **identique octet pour octet** à celui
qui a produit `built-in.a` et `bzImage` sur le build de contrôle.

## Avertissement sur le bzImage produit en `defconfig`

Un noyau compilé depuis `x86_64_defconfig` **démarre rarement sur une machine
réelle** : il n'embarque ni le pilote NVMe, ni le système de fichiers racine, ni
les firmwares attendus par le matériel. Il prouve la compilation, pas la
bootabilité.

Pour un noyau réellement démarrrable il faut la configuration du poste :
`/boot/config-$(uname -r)` ou `zcat /proc/config.gz > .config`, puis
`make olddefconfig` avant `make bzImage`.
