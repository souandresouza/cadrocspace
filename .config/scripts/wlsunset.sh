#!/bin/bash
# =============================================================================
# wlsunset.sh -- filtro de luz azul (dia/noite)
# =============================================================================
#
# Usa o geoclue quando disponível; senão, cai numa localização fixa. Para
# definir sua cidade sem geoclue, exporte as coordenadas no ambiente do
# compositor (env.conf) ou ajuste os padrões abaixo:
#
#   WLSUNSET_LAT="-23.5"  WLSUNSET_LON="-46.6"
#   WLSUNSET_DAY=6500     WLSUNSET_NIGHT=3800
#
# =============================================================================

# Aguardar inicialização
sleep 3

LAT="${WLSUNSET_LAT:--27.4}"
LON="${WLSUNSET_LON:--48.4}"
DAY="${WLSUNSET_DAY:-6500}"
NIGHT="${WLSUNSET_NIGHT:-3800}"

# Usar geoclue se disponível
if command -v geoclue2-agent &> /dev/null; then
    echo "wlsunset: usando geoclue2 (${DAY}K → ${NIGHT}K)"
    exec wlsunset -t "$DAY" -T "$NIGHT" -g 0.8 -d 2400
else
    echo "wlsunset: usando local fixo ($LAT, $LON)"
    exec wlsunset -l "$LAT" -L "$LON"
fi
