# Optimisations spécifiques au Celeron N4020 + identité Android

Deux demandes distinctes, et il faut les séparer : la première change réellement
le code machine produit ; la seconde ne change qu'une chaîne de caractères.

## 1. Optimisation CPU native (`CONFIG_X86_NATIVE_CPU`)

La configuration officielle CachyOS utilise `CONFIG_GENERIC_CPU=y` — un binaire
valable sur tous les x86-64, donc sans aucune instruction spécifique. Le noyau
expose l'option inverse :

```
config X86_NATIVE_CPU
	bool "Build and optimize for local/native CPU"
```
(in `arch/x86/Kconfig.cpu:221`)

Activation, vérifiée sur la base `cachyos-bore` :

```bash
cp docs/config-cachyos-bore-7.3.5-2 .config
scripts/config --enable X86_NATIVE_CPU --disable GENERIC_CPU
make olddefconfig && make -j"$(nproc)" bzImage modules
```

Résultat contrôlé sur cette base :

```
CONFIG_X86_NATIVE_CPU=y
# CONFIG_GENERIC_CPU is not set
```

### Ce que ça donne, honnêtement

Le N4020 est un **Goldmont Plus** (Gemini Lake). `-march=native` y active
SSE4.2, `crc32`, `pclmul`, AES-NI — et **rien de plus** : Goldmont Plus n'a ni
AVX, ni AVX2, ni BMI. Conséquences :

- **gain sur le chiffrement et les sommes de contrôle** (AES-NI, crc32c) : plausible
  et mesurable, c'est là que `-march=native` change vraiment la donne ;
- **gain sur le reste** : de l'ordre de quelques pour cent au mieux, souvent dans
  le bruit de mesure ;
- **coût** : ce noyau ne démarrera pas sur un autre CPU x86-64.

Tant que ce n'est pas mesuré sur ta machine, ces chiffres restent **non vérifiés**.

## 2. Identité Android 13 (`patchs/identite-android13.patch`)

Le noyau affiché par `uname -r` vient de quatre variables du `Makefile` :

```
VERSION = 5
PATCHLEVEL = 10
SUBLEVEL = 198
EXTRAVERSION = -android13-8
```

soit `5.10.198-android13-8`. Le patch fait exactement ces quatre remplacements,
rien d'autre.

```bash
patch -p1 < patchs/identite-android13.patch
```

### Ce que ça trompe — et ce que ça ne trompe pas

- **Ça trompe** un script qui lit `uname -r` ou `/proc/version` et cherche `android`.
- **Ça ne trompe pas** les applications Android modernes : elles lisent
  `ro.build.version.sdk` / `Build.VERSION`, fournis par l'image système (Waydroid,
  conteneur Android), pas par le noyau. Et surtout, Play Integrity / SafetyNet
  s'appuient sur une **attestation matérielle** (clés dans le TEE) : aucune chaîne
  de version de noyau ne peut la falsifier.
- **Effet de bord réel** : `UTS_RELEASE` devient `5.10.198-android13-8`, donc le
  répertoire des modules et le `vermagic` changent. Tout module construit hors
  arbre (nvidia, zfs, virtualbox, r8125) doit être recompilé.

Autrement dit : cette couche est cosmétique. Si des applications refusent de
tourner, la cause est presque toujours ailleurs (propriétés `ro.product.*`,
`libhoudini`/`libndk`, absence de Google Play, SELinux) — pas la version du noyau.
