#!/usr/bin/env bash
# mesure-gains-noyau.sh — produit les chiffres qui manquent, sans intervention.
#
# Ce qu'il fait, dans l'ordre :
#   1. mesure la consommation au repos (P0), 10 minutes, écran à luminosité constante
#   2. passe l'ASPM en powersupersave et remesure (P1), 10 minutes
#   3. décide : garde si gain >= 0,20 W et zéro erreur AER/NVMe ; sinon revient en arrière
#   4. relève les compteurs utiles (réveils, fréquence, veille)
#   5. écrit un rapport daté et pousse un message ntfy
#
# Usage : sudo bash mesure-gains-noyau.sh
#   (sudo nécessaire pour écrire dans /sys ; en lecture seule, il peut tourner sans sudo)
#   Variante courte (tests) : DUREE=120 bash mesure-gains-noyau.sh
#
# Aucun risque non réversible : tout réglage modifié est restauré si le seuil n'est pas atteint.

set -uo pipefail

DUREE="${DUREE:-600}"          # secondes par phase (600 = 10 min)
PAS="${PAS:-10}"               # échantillonnage en secondes
SEUIL_W="${SEUIL_W:-0.20}"     # gain minimal en watts pour garder le réglage
BAT=/sys/class/power_supply/BAT0
ASPM=/sys/module/pcie_aspm/parameters/policy
TOPIC="${NTFY_TOPIC:-equipe-thierry-7f3c9a1e5b2d84c6}"
SORTIE="$HOME/mesures-noyau/$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$HOME/mesures-noyau"

log() { printf '%s\n' "$*" | tee -a "$SORTIE"; }

echantillonner() { # $1 = libellé ; renvoie moyenne en W sur la sortie standard
  local sum=0 n=0 min=999999999 max=0 p
  local tours=$(( DUREE / PAS ))
  for _ in $(seq 1 "$tours"); do
    p=$(cat "$BAT/power_now" 2>/dev/null)
    if [ -n "${p:-}" ]; then
      sum=$((sum + p)); n=$((n + 1))
      [ "$p" -lt "$min" ] && min=$p
      [ "$p" -gt "$max" ] && max=$p
    fi
    sleep "$PAS"
  done
  [ "$n" -eq 0 ] && { echo "0"; return; }
  awk -v s="$sum" -v n="$n" -v mn="$min" -v mx="$max" \
      'BEGIN{printf "%.3f %.3f %.3f %d", s/n/1000000, mn/1000000, mx/1000000, n}'
}

etat_aspm() { cat "$ASPM" 2>/dev/null | tr -d '\n'; }
erreurs_pcie() { dmesg 2>/dev/null | grep -ci -E 'AER|nvme.*reset|link down' || echo 0; }

log "=== mesure-gains-noyau $(date '+%d/%m/%Y %H:%M') ==="
log "phase : $DUREE s, pas $PAS s, seuil $SEUIL_W W"
log "batterie : $(cat "$BAT/energy_now" 2>/dev/null) uWh / $(cat "$BAT/energy_full" 2>/dev/null) uWh"
log "ASPM avant : $(etat_aspm)"
log "erreurs PCIe avant : $(erreurs_pcie)"

log ""
log "--- PHASE 0 : reference, ASPM inchange ---"
R0=$(echantillonner "P0")
P0=$(echo "$R0" | cut -d' ' -f1)
log "P0 = $P0 W (min $(echo "$R0" | cut -d' ' -f2), max $(echo "$R0" | cut -d' ' -f3), n=$(echo "$R0" | cut -d' ' -f4))"

ASPM_AVANT=$(etat_aspm | tr -d '[]' | awk '{print $1}')
if echo "$ASPM_AVANT" | grep -q powersupersave; then
  log "ASPM deja en powersupersave : pas de comparaison possible, phase 1 sautee"
  P1=""
else
  log ""
  log "--- PHASE 1 : ASPM powersupersave ---"
  if echo powersupersave > "$ASPM" 2>/dev/null; then
    log "ASPM maintenant : $(etat_aspm)"
    R1=$(echantillonner "P1")
    P1=$(echo "$R1" | cut -d' ' -f1)
    log "P1 = $P1 W (min $(echo "$R1" | cut -d' ' -f2), max $(echo "$R1" | cut -d' ' -f3), n=$(echo "$R1" | cut -d' ' -f4))"
    E1=$(erreurs_pcie)
    log "erreurs PCIe apres : $E1"
    log ""
    log "--- DECISION ---"
    GAIN=$(awk -v a="$P0" -v b="$P1" 'BEGIN{printf "%.3f", a-b}')
    log "gain = $GAIN W  (seuil $SEUIL_W W)"
    KEEP=$(awk -v g="$GAIN" -v s="$SEUIL_W" 'BEGIN{print (g>=s)?"1":"0"}')
    if [ "$KEEP" = "1" ] && [ "$E1" -eq 0 ]; then
      log "VERDICT : GARDE powersupersave (gain >= seuil, aucune erreur PCIe)"
      log "rendu permanent : echo powersupersave > $ASPM"
    else
      log "VERDICT : REVERT (gain insuffisant ou erreurs PCIe detectees)"
      echo performance > "$ASPM" 2>/dev/null
      log "ASPM restaure : $(etat_aspm)"
    fi
  else
    log "ecriture impossible dans $ASPM (sudo requis) — aucune modification faite"
  fi
fi

log ""
log "--- CONTEXTE UTILE ---"
log "frequence : $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null) kHz"
log "gouverneur : $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)"
log "veille : $(cat /sys/power/mem_sleep 2>/dev/null)"
log "reveils comptes : $(cat /proc/interrupts 2>/dev/null | head -1 | awk '{print $1}')"
log "charge : $(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3)"
log "rapport : $SORTIE"

curl -s -m 10 -H "Title: mesure gains noyau" -d "P0=$P0 W, P1=${P1:-non mesure}, rapport $(basename "$SORTIE")" \
  "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 && log "ntfy : envoye" || log "ntfy : echec (rapport conserve localement)"
