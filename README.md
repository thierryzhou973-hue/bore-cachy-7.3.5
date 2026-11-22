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
